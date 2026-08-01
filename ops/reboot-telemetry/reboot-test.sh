#!/usr/bin/env bash
# reboot-test.sh — unattended reboot soak test (ADR 0016 verification matrix).
#
# While armed, each healthy boot verifies the PREVIOUS cycle from the telemetry
# log (marker present, sane marker→kernel gap), waits for the Elements drive,
# settles, then initiates the next reboot itself. The mount-rebooter supplies
# the "second reboot when the USB disk comes up absent" case automatically —
# such recovery boots do not consume a test cycle; only healthy boots advance.
#
# Any evidence of a hang (gap missing or > GAP_LIMIT) ABORTS the run and
# disarms, so a manual power-cycle after a stranding never triggers yet more
# unattended reboots — the evidence is already captured, which was the point.
#
# Usage (arm/disarm need sudo):
#   reboot-test.sh arm [N] [K]   arm N automated reboots (default 5), the last
#                                K of them kernel-update-like (default 2:
#                                reinstalls the running kernel package first to
#                                regenerate initramfs + grub.cfg). Kick off
#                                with: sudo reboot
#   reboot-test.sh disarm        stop the run (also safe mid-settle)
#   reboot-test.sh status        show state + recent log lines
#   reboot-test.sh boot          boot-time entry point (reboot-test.service)
set -u
STATE=/var/lib/reboot-test
TLOG=/var/lib/reboot-telemetry/log
LOG=$STATE/log
ELEMENTS_UUID=72908AD6908A9FE9
GAP_LIMIT=300    # s; a larger marker→kernel gap means a hang happened
DRIVE_WAIT=240   # s to wait for Elements before deferring to mount-rebooter
SETTLE=180       # s of quiet after a healthy boot before the next reboot
SD_WAIT=1800     # s to wait for an in-progress SD card sync to finish

log() { mkdir -p "$STATE"; echo "$(date -Is) $*" >> "$LOG"; }

drive_healthy() {
    # test -f first: it triggers the automount if only the autofs stub is up
    [ -f /mnt/Elements/.mount-ok ] && [ -d /mnt/Elements/Video ] &&
    [ "$(findmnt -rn -T /mnt/Elements -o UUID 2>/dev/null)" = "$ELEMENTS_UUID" ] &&
    findmnt -rn -T /mnt/Elements -o OPTIONS | tr ',' '\n' | grep -qx rw
}

abort() {
    log "ABORT: $1 Disarming."
    rm -f "$STATE/remaining"
    exit 1
}

case "${1:-}" in
  arm)
    [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
    N="${2:-5}"; K="${3:-2}"
    mkdir -p "$STATE"
    echo "$N" > "$STATE/remaining"
    echo "$K" > "$STATE/kernel_like"
    echo 0 > "$STATE/boots"
    echo $(( N * 4 + 4 )) > "$STATE/max_boots"
    log "ARMED: $N automated reboots, last $K kernel-like."
    echo "Armed: $N automated test reboots (last $K kernel-like)."
    echo "Kick off with: sudo reboot"
    ;;

  disarm)
    [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
    if [ -f "$STATE/remaining" ]; then
        rm -f "$STATE/remaining"
        log "DISARMED by user."
        echo "Disarmed."
    else
        echo "Not armed."
    fi
    ;;

  status)
    if [ -f "$STATE/remaining" ]; then
        echo "ARMED: $(cat "$STATE/remaining") reboot(s) remaining" \
             "($(cat "$STATE/kernel_like" 2>/dev/null || echo 0) kernel-like at the end)," \
             "boot counter $(cat "$STATE/boots" 2>/dev/null || echo 0)"
    else
        echo "not armed"
    fi
    echo "--- test log ---";      tail -12 "$LOG" 2>/dev/null || echo "(none)"
    echo "--- telemetry log ---"; tail -6 "$TLOG" 2>/dev/null || echo "(none)"
    ;;

  boot)
    [ -f "$STATE/remaining" ] || exit 0
    boots=$(( $(cat "$STATE/boots" 2>/dev/null || echo 0) + 1 ))
    echo "$boots" > "$STATE/boots"
    [ "$boots" -le "$(cat "$STATE/max_boots" 2>/dev/null || echo 0)" ] || \
        abort "boot counter $boots exceeded runaway guard."

    # Verify the reboot that produced THIS boot, from the telemetry log.
    lastboot=$(grep ' boot kernel-start=' "$TLOG" 2>/dev/null | tail -1)
    gap=$(printf '%s' "$lastboot" | sed -n 's/.*marker-to-kernel-gap=\([0-9]*\)s.*/\1/p')
    [ -n "$gap" ] || \
        abort "gap unknown for last boot — marker missing => shutdown-side hang (H2). Evidence captured. [$lastboot]"
    [ "$gap" -le "$GAP_LIMIT" ] || \
        abort "marker-to-kernel-gap=${gap}s > ${GAP_LIMIT}s => a hang occurred (H1 window). Evidence captured. [$lastboot]"

    # Wait for Elements; if absent, the mount-rebooter owns recovery and its
    # reboot re-runs us — this boot consumes no test cycle.
    deadline=$(( $(date +%s) + DRIVE_WAIT ))
    until drive_healthy; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
            log "boot #$boots: gap=${gap}s but Elements absent after ${DRIVE_WAIT}s — deferring to mount-rebooter."
            exit 0
        fi
        sleep 5
    done

    remaining=$(cat "$STATE/remaining")
    log "boot #$boots healthy: gap=${gap}s, Elements mounted, $remaining test reboot(s) to go."
    if [ "$remaining" -le 0 ]; then
        log "COMPLETE: all automated reboots verified across $boots boots. Disarming."
        rm -f "$STATE/remaining"
        exit 0
    fi

    sleep "$SETTLE"
    [ -f "$STATE/remaining" ] || { log "disarmed during settle; stopping."; exit 0; }

    # Never pull the floor out from under an SD card sync.
    sddeadline=$(( $(date +%s) + SD_WAIT ))
    while findmnt -n -t exfat /mnt/sdcard >/dev/null 2>&1; do
        [ "$(date +%s)" -lt "$sddeadline" ] || abort "SD card still busy after ${SD_WAIT}s."
        sleep 30
    done

    kind=plain
    if [ "$remaining" -le "$(cat "$STATE/kernel_like" 2>/dev/null || echo 0)" ]; then
        kind=kernel-like
        log "kernel-like prep: reinstalling linux-image-$(uname -r) (regenerates initramfs + grub.cfg)"
        if ! DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y \
                "linux-image-$(uname -r)" >> "$LOG" 2>&1; then
            log "kernel reinstall FAILED — falling back to a plain reboot."
            kind=plain
        fi
    fi

    echo $(( remaining - 1 )) > "$STATE/remaining"
    sync
    log "initiating $kind test reboot ($(( remaining - 1 )) left after this)."
    systemctl reboot
    ;;

  *) echo "usage: $0 arm [N] [K] | disarm | status | boot" >&2; exit 2 ;;
esac
