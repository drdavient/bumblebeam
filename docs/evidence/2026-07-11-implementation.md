# Implementation evidence: 2026-07-11

## Passed

- Every eligible Compose project validates with its sanitised example environment:
  Home Assistant, Home Media, Cloudflare DDNS, mount-watcher, n8n,
  Plex, Structurizr, and Traefik.
- Shell syntax validation passes for every script under `ops/backup/` and for
  `mount-watcher/mount-rebooter.sh`.
- Backup preflight against the current Elements state exits 3 with
  `Elements is not mounted read-write; refusing backup`.
- Git ignore spot checks pass for HA secrets/databases, n8n state, Plex preferences
  and databases, Home Media credentials/runtime configuration, archives, and
  Traefik local environment/ACME state.
- Eligible root and Home Media files contain no matches for the audited high-risk
  token/key shapes. This is a heuristic, not proof that credentials are absent.
- HA secrets, n8n config, Home Media `.env`, and Deluge auth are mode 600.
- Plex now advertises `http://192.168.1.15:32400/`; Traefik and n8n list canonical
  `*.home.arpa`, compatibility `*.svc.home.arpa`, and bare LAN hosts.
- Shared Docker networks were recreated with stable identity: `gluetun-net` uses
  subnet `172.18.0.0/16` and bridge `br-gluetun`; `traefik-net` uses subnet
  `172.26.0.0/16` and bridge `br-traefik`. Their owning Compose projects are Home
  Media and Traefik respectively; Traefik and n8n restarted cleanly.
- Traefik now has a dedicated `host-services-net` (`172.22.0.0/24`,
  `br-host-svc`) with fixed source `172.22.0.10`; host-service traffic no longer
  uses the Gluetun network. The Git-managed Bumblebeam portal returns HTTP 200,
  and the retired Elements-hosted page was removed.
- The narrow UFW rule for `172.22.0.10` on `br-host-svc` restores the Home
  Assistant proxy path; direct and canonical proxy requests both return HTTP 200.
- Host-level `findmnt` confirms `/dev/sdb1` UUID `72908AD6908A9FE9` is mounted
  read-write. The earlier read-only observation was the restricted sandbox bind.
- Ubuntu Restic 0.12.1 is installed workspace-locally at `.local/usr/bin/restic`.
- Official rclone 1.74.4 is installed workspace-locally after its published
  SHA-256 checksum passed; it resolved the OneDrive upload authentication error.
- Restic securely self-updated to 0.19.1 with successful GPG verification. A clean
  OneDrive repository was initialized and all three local snapshots were copied.
- Consistent snapshot `91ae36f7` stopped only n8n, Home Assistant, Plex, and
  Traefik, processed 6,131 files / 2.331 GiB, and stored 1.581 GiB.
- Final consistent incremental snapshot `41886abd` captured the completed
  configuration with recovery-password exclusions and added 15.701 MiB.
- Snapshot `882bbdb4` captured the earlier mount-watcher safety fixes and restore
  assertion; it added 11.682 MiB. The later one-shot design awaits the next backup.
- All four previously running containers restarted and report `running=true`.
- Full local `restic check --read-data` read 377 packs and found no errors.
- The final full check covered all three snapshots and all 388 packs with no errors.
- A temporary restore verified representative HA secrets/database, n8n SQLite,
  Plex preferences/database, and Traefik configuration.
- Remote verification after reconnecting rclone passed: `restic check
  --read-data-subset=1/10` reported no errors, and
  `ops/backup/restore-test.sh remote` restored the representative configuration
  and database set successfully.
- After restart, HA direct and Plex direct returned HTTP 200; Plex canonical proxy,
  n8n bare proxy, and n8n compatibility proxy also returned HTTP 200.
- Retention dry-run applied 7 daily, 4 weekly, and 12 monthly and selected the
  latest same-day snapshot. The final snapshot's representative restore passed.
- The rebuilt privileged mount-watcher uses the correct Alpine shell, confirms the
  host UUID is read-write, exits successfully, and has Docker restart policy `no`.
  A systemd one-shot unit is supplied as the deliberate host-boot trigger.

## Blocked or not yet executed

- n8n canonical `n8n.home.arpa` now returns HTTP 200 after recreation.
- LAN DNS and end-user automation/playback/webhook tests remain unverified.
- Plex/Cloudflare token rotation remains deferred because the current checkout
  contains no evidence of external exposure; account-wide Plex reauthentication
  was declined. OneDrive desktop exclusion, account MFA/recovery, and creation of
  the dedicated backup identity still require account-owner interaction.
- The obsolete empty `Home_Media/.git` boundary and the earlier
  `ITS_Home_Media/` codex-gsd attempt were removed; `Home_Media/` remains as
  protected runtime state. The root project and agent configuration are committed
  on `main`.
