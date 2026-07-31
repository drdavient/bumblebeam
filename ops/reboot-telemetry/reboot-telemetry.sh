#!/usr/bin/env bash
# reboot-telemetry.sh — file-based forensics for the reboot-hang investigation
# (ADR 0016). Two entry points driven by systemd units:
#   marker : written LATE in shutdown (just before filesystems unmount).
#   boot   : written EARLY at boot, before grub-common clears recordfail.
# The marker→kernel-start gap attributes any outage to the invisible
# BIOS/POST/GRUB window; grubenv recordfail state distinguishes whether GRUB
# ever handed off to a kernel.
set -u
LOG=/var/lib/reboot-telemetry/log
mkdir -p /var/lib/reboot-telemetry

case "${1:-}" in
  marker)
    echo "$(date -Is) shutdown-complete" >> "$LOG"
    sync
    ;;
  boot)
    kboot=$(date -Is -d "@$(( $(date +%s) - $(cut -d. -f1 /proc/uptime) ))")
    grubenv=$(grub-editenv /boot/grub/grubenv list 2>&1 | tr '\n' ' ')
    lastmark=$(grep ' shutdown-complete$' "$LOG" 2>/dev/null | tail -1 | cut -d' ' -f1)
    gap=unknown
    if [ -n "$lastmark" ]; then
      gap="$(( $(date -d "$kboot" +%s) - $(date -d "$lastmark" +%s) ))s"
    fi
    echo "$(date -Is) boot kernel-start=$kboot marker-to-kernel-gap=$gap grubenv=[${grubenv:-empty}]" >> "$LOG"
    ;;
  *) echo "usage: $0 marker|boot" >&2; exit 2 ;;
esac
