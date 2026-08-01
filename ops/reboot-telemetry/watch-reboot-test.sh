#!/usr/bin/env bash
# watch-reboot-test.sh — run ON A PHONE (Termux) or any other box to watch a
# Bumblebeam unattended reboot trial (ADR 0016) from the outside. Needs only
# bash + ssh (key auth). Reachability is probed as "TCP port 22 answers", so
# UP means sshd is up, not merely that the NIC pings.
#
# One-time Termux setup:
#   pkg install openssh termux-api    # termux-api optional (notifications)
#   ssh-keygen -t ed25519             # if you have no key yet
#   ssh-copy-id drdavient@192.168.1.15
#   scp drdavient@192.168.1.15:docker/ops/reboot-telemetry/watch-reboot-test.sh .
# Run (wake-lock stops Android suspending it):
#   termux-wake-lock; bash watch-reboot-test.sh
#
# Reading the screen:
#   DOWN < 5 min  = normal reboot window (a USB-recovery double reboot shows
#                   as two DOWN episodes back to back)
#   DOWN >= 5 min = almost certainly the BIOS/POST hang — press the power
#                   button; the trial auto-disarms itself once the box is back.
HOST=${HOST:-192.168.1.15}
RUSER=${RUSER:-drdavient}
STATUS_CMD='/home/drdavient/docker/ops/reboot-telemetry/reboot-test.sh status'
INTERVAL=5    # seconds between reachability probes
FETCH=15      # seconds between status fetches while up
STALL=300     # continuous downtime that means "probably hung"

now() { date +%s; }
hms() { printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); }

notify() {
    printf '\a'
    command -v termux-vibrate >/dev/null 2>&1 && termux-vibrate -d 800 2>/dev/null
    command -v termux-notification >/dev/null 2>&1 && \
        termux-notification --title "Bumblebeam trial" --content "$1" 2>/dev/null
}

reachable() { timeout 3 bash -c "exec 3<>/dev/tcp/$HOST/22" 2>/dev/null; }

state=init; since=$(now); downs=0; stall_flagged=0
status_text="(no status fetched yet)"; status_at=""; last_fetch=0
prev_armed=""; events=""

event() {  # keep a short on-screen history of state transitions
    events="$(date '+%H:%M:%S') $1
$events"
    events=$(printf '%s\n' "$events" | head -8)
}

while :; do
    t=$(now)
    if reachable; then
        if [ "$state" != up ]; then
            [ "$state" = down ] && event "UP again after $(hms $((t - since)))"
            state=up; since=$t; stall_flagged=0
        fi
        if [ $((t - last_fetch)) -ge $FETCH ]; then
            if out=$(ssh -o BatchMode=yes -o ConnectTimeout=4 \
                         -o StrictHostKeyChecking=accept-new \
                         "$RUSER@$HOST" "$STATUS_CMD" 2>/dev/null); then
                status_text=$out; status_at=$(date '+%H:%M:%S'); last_fetch=$t
                armed_now=$(printf '%s\n' "$status_text" | head -1)
                if [ -n "$prev_armed" ] && [ "${prev_armed#ARMED}" != "$prev_armed" ] \
                   && [ "${armed_now#ARMED}" = "$armed_now" ]; then
                    reason=$(printf '%s\n' "$status_text" | grep -E 'COMPLETE|ABORT|DISARMED' | tail -1)
                    event "TRIAL FINISHED: ${reason:-see logs}"
                    notify "Trial finished: ${reason:-see logs}"
                fi
                prev_armed=$armed_now
            else
                status_text="ssh status fetch FAILED (still booting? key auth? try: ssh $RUSER@$HOST)"
                status_at=$(date '+%H:%M:%S'); last_fetch=$t
            fi
        fi
    else
        if [ "$state" != down ]; then
            [ "$state" = up ] && event "DOWN (was up $(hms $((t - since))))"
            state=down; since=$t; downs=$((downs + 1))
        fi
    fi

    clear
    echo "=== BUMBLEBEAM REBOOT-TRIAL WATCH === $(date '+%H:%M:%S')"
    dur=$((t - since))
    if [ "$state" = up ]; then
        echo "state: UP for $(hms $dur)    down episodes so far: $downs"
    elif [ "$dur" -ge "$STALL" ]; then
        echo "state: DOWN for $(hms $dur)"
        echo ">>> LIKELY HUNG — go press the power button <<<"
        if [ "$stall_flagged" = 0 ]; then
            event "STALL: down over $(hms $STALL)"
            notify "DOWN $(hms $dur) — likely hung, power-cycle needed"
            stall_flagged=1
        fi
    else
        echo "state: DOWN for $(hms $dur)   (normal reboot window, alarm at $(hms $STALL))"
    fi
    echo
    echo "--- trial status (fetched ${status_at:-never}) ---"
    printf '%s\n' "$status_text"
    echo
    echo "--- events ---"
    printf '%s\n' "${events:-"(none yet)"}"
    sleep "$INTERVAL"
done
