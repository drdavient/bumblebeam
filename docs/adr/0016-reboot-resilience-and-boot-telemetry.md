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

## Amendment (2026-07-31, first test cycle)

The first supervised test reboot and its aftermath taught four things:

1. **Warm reboots can bring the box up with the Elements USB disk absent**
   (observed 20:12 boot) — the mild form of the same platform warm-reboot/USB
   defect as H1; further weight behind the BIOS update.
2. **The rebooter's container could not start in exactly that scenario** —
   bind-mounting `/mnt/Elements` fails ("no such device") when the drive is
   absent, so the safety net silently no-ops. Fixed: no Elements bind; all
   checks via nsenter into the host mount namespace; reboot is now orderly
   (`systemctl reboot` via nsenter, `reboot -f` fallback) so it writes the
   telemetry marker and re-arms the shutdown watchdog.
3. **Deploy discipline**: `docker compose run` and the boot-check service use
   the *built image* — editing `mount-rebooter.sh` without `docker compose
   build` runs stale code. This caused two spurious host reboots during
   testing (old in-image script + new bind-less compose = guaranteed false
   "drive missing"). Always rebuild before exercising the rebooter.
4. **Telemetry fixes from live data**: the shutdown-marker unit needed
   explicit `Conflicts=shutdown.target`/`Before=shutdown.target`
   (`DefaultDependencies=no` drops the implicit ones, so ExecStop never ran);
   and `grubenv=[recordfail=1]` in the boot capture is *normal* (GRUB sets it
   for the in-progress boot; grub-common clears it after our capture).

## Amendment (2026-08-01, unattended soak harness)

After two clean supervised reboots, the Phase 2/4 verification matrix was
automated as `ops/reboot-telemetry/reboot-test.sh` + `reboot-test.service`
(inert unless armed). Armed, each healthy boot verifies the previous cycle
from the telemetry log (marker present, gap ≤ 300s), waits for Elements
(absent drive defers to the mount-rebooter, whose recovery reboot consumes no
cycle), then initiates the next reboot — default 5 cycles, the last 2
kernel-update-like (kernel package reinstalled first). Any hang evidence
disarms the run so a manually rescued box never self-reboots again; a 4×N
boot-counter guard backstops runaways. The unattended-hang risk is accepted
by whoever arms it.

First armed run caught a probe bug: `findmnt -T` on an automounted path
returns **both** the autofs stub and the real mount, so a whole-output UUID
comparison never matches — health checks must select the record by UUID (as
the mount-rebooter's awk parse already did). The failure mode was benign by
design: the harness deferred to the (correctly passing) rebooter and parked,
consuming no cycles.

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
