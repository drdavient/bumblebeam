# 0016. Reboot resilience and boot-window telemetry

Date: 2026-07-31
Status: Accepted (Phase 3 BIOS session pending)

## Context

`sudo reboot` intermittently leaves Bumblebeam dead until a manual power-cycle
(observed 2026-05-13 ~17 min and 2026-07-23 ~19 min; the owner reports the
pattern has recurred several times). Investigation evidence:

- The 2026-07-23 journal shows a **fully clean systemd shutdown**, then a
  19-minute void with zero boot traces (no wtmp, no journal), then a normal
  ~60s boot after a blind power-cycle.
- Ubuntu GRUB sets `recordfail=1` in grubenv immediately before kernel
  handoff; with `GRUB_TIMEOUT=0` and no `GRUB_RECORDFAIL_TIMEOUT` (default
  −1), a set flag means an infinite headless menu wait. The forced second
  boots came up cleanly in ~60s ⇒ recordfail was never set ⇒ **GRUB never
  reached kernel handoff**. The hang lives in kernel-final-reset → BIOS POST →
  GRUB core load.
- Hardware: NUC6i7KYB (Skull Canyon), **legacy BIOS 0037 (2016-06)** — the
  third-ever release; Intel shipped dozens of boot/hang/reset fixes through
  the final (~0067/0071). Two USB storage devices (7.3TB NTFS, SD reader) are
  enumerated at POST by the legacy BIOS.
- No hardware watchdog was armed. A broken udev hook
  (`99-usb-mount.rules` → `usb-mount.sh`, `udisksctl` absent) fired uselessly
  at every boot. The mount-rebooter boot job (`reboot -f` up to 3×) was ruled
  out for these incidents (its reboots would leave boot records).

Hypotheses, ranked: **H1** warm-reboot BIOS/POST hang with USB storage
attached (strongest); **H2** kernel reboot-method quirk (`reboot=pci`/`acpi`);
**H3** GRUB recordfail headless brick (latent risk, not the observed cause);
**H4** early hang of a newly-installed kernel (near-excluded by the
recordfail deduction).

## Decision

1. **Designated fix (Phase 3, physical session)**: update the BIOS 0037 → the
   final release (0067, possibly 0071), stepped (0037 → ~0050 → 0063 → final;
   community reports direct jumps from 0037 failing; downgrade blocks at
   0053/0062 are permanent), and while in setup: boot order = internal SATA
   only, USB boot and PXE disabled.
2. **Immediately (remote, `ops/reboot-telemetry/install.sh`)**:
   `GRUB_RECORDFAIL_TIMEOUT=5` (headless-brick protection — matters most
   *around the BIOS work itself*); boot-window telemetry (shutdown marker +
   boot forensics incl. pre-clear grubenv capture) so any future hang
   self-documents which window ate the time; iTCO hardware watchdog
   (`RuntimeWatchdogSec=2min`, `RebootWatchdogSec=3min`) so kernel-side hangs
   self-recover — its *failure* to rescue a hang is itself evidence for H1;
   removal of the dead usb-mount udev hook.
3. **Contingent (only if telemetry shows a marker-absent hang, i.e. H2)**:
   trial `reboot=pci`, then `reboot=acpi`, in `GRUB_CMDLINE_LINUX_DEFAULT`,
   one variant per supervised reboot.
4. Verification: after the BIOS session, ≥3 plain reboots and 2
   "kernel-update-like" reboots (kernel pkg reinstall first), gaps read from
   `/var/lib/reboot-telemetry/log` (norm ≤90s).

## Consequences

- Any future hang is attributable from a file instead of unexplained: see
  `ops/reboot-telemetry/README.md` for the decision tree (also summarised in
  the stabilisation runbook).
- The watchdog introduces automatic hard resets on PID-1/kernel hangs; the
  mount-rebooter's `reboot -f` path bypasses `RebootWatchdogSec` re-arm and is
  the most hang-prone reset flavour — switching it to an orderly
  `systemctl reboot` is a recorded follow-up candidate.
- Until the BIOS session happens, reboots remain a known ~intermittent risk;
  schedule them when someone can reach the power button.
