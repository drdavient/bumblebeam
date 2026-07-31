# Reboot telemetry & resilience

Why this exists, the evidence, and the decision record: **ADR 0016**. Symptom:
`sudo reboot` intermittently hangs in the invisible window between systemd's
clean shutdown and the next boot (BIOS 0037 POST is the prime suspect); the box
needs a manual power-cycle ~15–20 min later. The designated fix is the BIOS
session (flash 0037 → final + boot-order cleanup — ADR 0016 Phase 3); this
directory makes the machine safe and self-documenting in the meantime.

## What's installed (via `sudo ./install.sh`, idempotent)

- `GRUB_RECORDFAIL_TIMEOUT=5` in `/etc/default/grub` — a failed boot costs a
  5s menu, never an infinite headless wait.
- `reboot-marker.service` — appends `shutdown-complete` to
  `/var/lib/reboot-telemetry/log` late in every shutdown.
- `boot-forensics.service` — early each boot (before grub-common clears
  recordfail) appends kernel start time, the **marker→kernel gap** (= dwell in
  the kernel-reset/BIOS/GRUB window), and grubenv contents.
- iTCO hardware watchdog (`RuntimeWatchdogSec=2min`, `RebootWatchdogSec=3min`)
  — a kernel-side hang self-recovers in minutes; gated on the module actually
  working (skipped with a message if inert).
- Removes the dead `99-usb-mount.rules`/`usb-mount.sh` udev hook.

## Reading the log after an incident

- Normal reboot: `marker-to-kernel-gap` ≈ 10–60s.
- Marker present + huge gap + `grubenv` clean ⇒ hang was BIOS/POST/GRUB-load
  (H1) → do the BIOS session.
- Marker **absent** for a shutdown you know happened ⇒ hang was in late
  systemd-shutdown / kernel reset (H2) → try `reboot=pci` (then `acpi`) in
  `GRUB_CMDLINE_LINUX_DEFAULT`.
- `grubenv=[recordfail=1]` is **normal** — GRUB sets it for the in-progress
  boot and grub-common clears it moments after our capture. Its only signal
  value: with `GRUB_RECORDFAIL_TIMEOUT=5` a leftover flag from a genuinely
  failed boot costs a 5s menu; the meaningful discriminators are the marker
  and the gap.
- Box came back by itself ~3min after a hang ⇒ the watchdog rescued it (H2
  confirmed).
