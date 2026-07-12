#!/bin/sh

LOG_FILE="/var/log/mount-rebooter/mount-rebooter.log"
STATE_FILE="/state/reboot_count"
UUID="72908AD6908A9FE9"
MAX_REBOOTS=3
WAIT_SECONDS=120
CHECK_INTERVAL=5

log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" >> "$LOG_FILE"
}

logn() {
    printf "$1" >> "$LOG_FILE"
}

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATE_FILE")"

[ -f "$STATE_FILE" ] || echo 0 > "$STATE_FILE"
REBOOT_COUNT=$(cat "$STATE_FILE")

log "mount-rebooter started, rebootCount=$REBOOT_COUNT"

is_mounted_ok() {
    # Query the host mount namespace; /mnt/Elements is intentionally bind-mounted
    # read-only inside this container.
    HOST_RECORD="$(nsenter -t 1 -m -- findmnt -rn -T /mnt/Elements -o UUID,OPTIONS 2>/dev/null | awk 'NF >= 2 { print; exit }')"
    read -r HOST_UUID HOST_OPTIONS <<EOF
$HOST_RECORD
EOF
    [ "$HOST_UUID" = "$UUID" ] && \
        printf '%s' "$HOST_OPTIONS" | tr ',' '\n' | grep -qx rw && \
        [ -f /mnt/Elements/.mount-ok ] && [ -d /mnt/Elements/Video ]
}

is_expected_disk_read_only() {
    HOST_RECORD="$(nsenter -t 1 -m -- findmnt -rn -T /mnt/Elements -o UUID,OPTIONS 2>/dev/null | awk 'NF >= 2 { print; exit }')"
    read -r HOST_UUID HOST_OPTIONS <<EOF
$HOST_RECORD
EOF
    [ "$HOST_UUID" = "$UUID" ] && \
        printf '%s' "$HOST_OPTIONS" | tr ',' '\n' | grep -qx ro
}

if is_mounted_ok; then
    log "Drive OK at boot. Resetting counter."
    echo 0 > "$STATE_FILE"
    exit 0
fi

log "Drive not mounted. Waiting up to ${WAIT_SECONDS}s..."

deadline=$(( $(date +%s) + WAIT_SECONDS ))

while [ "$(date +%s)" -lt "$deadline" ]; do
    if is_mounted_ok; then
        log "Drive mounted within timeout. Resetting counter."
        echo 0 > "$STATE_FILE"
        exit 0
    fi
    sleep "$CHECK_INTERVAL"
done

# Timeout
log "Drive NOT mounted after timeout."

if is_expected_disk_read_only; then
    log "Expected disk is read-only. Refusing forced reboot; repair the filesystem first."
    exit 1
fi

if [ "$REBOOT_COUNT" -lt "$MAX_REBOOTS" ]; then
    NEW_COUNT=$((REBOOT_COUNT + 1))
    echo "$NEW_COUNT" > "$STATE_FILE"
    log "Rebooting host, rebootCount=${NEW_COUNT}/${MAX_REBOOTS}"

    # Direct kernel reboot syscall is most reliable
    /sbin/reboot -f
else
    log "MAX_REBOOTS reached (${REBOOT_COUNT}). NOT rebooting."
fi
