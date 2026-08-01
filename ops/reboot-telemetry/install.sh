#!/usr/bin/env bash
# One-shot installer for the reboot-hang mitigations (ADR 0016). Idempotent.
# Run as: sudo ops/reboot-telemetry/install.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }

echo "== GRUB recordfail safety net (headless-brick protection)"
if grep -q '^GRUB_RECORDFAIL_TIMEOUT=' /etc/default/grub; then
  echo "   already set: $(grep '^GRUB_RECORDFAIL_TIMEOUT=' /etc/default/grub)"
else
  echo 'GRUB_RECORDFAIL_TIMEOUT=5' >> /etc/default/grub
  echo "   added GRUB_RECORDFAIL_TIMEOUT=5"
fi
update-grub

echo "== removing broken usb-mount udev hook (udisksctl absent; fstab automount owns the mount)"
rm -f /etc/udev/rules.d/99-usb-mount.rules /usr/local/bin/usb-mount.sh
udevadm control --reload

echo "== boot-window telemetry units"
mkdir -p /var/lib/reboot-telemetry
cp "$DIR/systemd/reboot-marker.service" "$DIR/systemd/boot-forensics.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now reboot-marker.service boot-forensics.service

echo "== unattended soak-test unit (inert until reboot-test.sh arm)"
cp "$DIR/systemd/reboot-test.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable reboot-test.service

echo "== hardware watchdog gate"
modprobe iTCO_wdt 2>/dev/null || true
if [ -e /dev/watchdog0 ] && ! dmesg | grep -qi "failed to reset NO_REBOOT"; then
  cp "$DIR/etc/watchdog-modules.conf" /etc/modules-load.d/watchdog.conf
  mkdir -p /etc/systemd/system.conf.d
  cp "$DIR/etc/10-watchdog.conf" /etc/systemd/system.conf.d/10-watchdog.conf
  systemctl daemon-reexec
  echo "   watchdog armed: $(systemctl show -p RuntimeWatchdogUSec)"
else
  echo "   WATCHDOG GATE FAILED — iTCO inert on this board; skipping (record in ADR 0016)"
  dmesg | grep -i itco | tail -3 || true
fi

echo "== summary"
systemctl --failed --no-legend || true
tail -3 /var/lib/reboot-telemetry/log 2>/dev/null || true
echo "done."
