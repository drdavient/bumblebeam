# Stabilisation runbook

Run commands from `/home/drdavient/docker`. Never paste credential values into
shell history, logs, tickets, Git, or evidence files.

## 1. Security gate

The current checkout contains no Git history or evidence that Plex or Cloudflare
credentials were externally exposed. Earlier notes record that credentials were
embedded locally in declarative files, which is an unsafe configuration practice
but does not establish disclosure. Account-wide Plex reauthentication and emergency
Cloudflare rotation are therefore deferred, not first-commit prerequisites.

Before the first Git commit:

1. Keep Plex runtime state and Cloudflare credentials out of Git. Revisit Plex
   account-wide rotation during planned maintenance if the exposure report is later
   substantiated.
2. Keep Cloudflare credentials scoped to the required zone/DNS operations and
   revisit routine rotation through the account owner when convenient.
3. Put local values only in ignored `traefik/.env` and `cloudflare-ddns/.env`; use
   the checked-in examples as templates. Set each file to mode 600.
4. Tighten existing secrets:

   ```sh
   chmod 600 HomeAssistant/hadata/secrets.yaml n8n/data/config \
     Home_Media/.env Home_Media/deluge-config/auth
   ```

5. Review secret-bearing locations without printing values:

   ```sh
   rg -l -i --hidden -g '!**/.git/**' -g '!**/*.db*' \
     '(token|password|passwd|secret|api[_-]?key|credential|plex_claim|x-plex-token)'
   git status --short --ignored
   git diff --cached --name-only
   ```

For future commits, review `git diff --cached` and keep credentials and runtime
state outside Git. The initial configuration and operations commit is now present.

Shared Docker networks are owned by their service stacks: `traefik/compose.yml`
defines `traefik-net` and the Traefik-only `host-services-net`; `Home_Media/compose.yml`
defines `gluetun-net`. Keep their subnets and bridge names stable; dependent
Compose projects should continue to refer to them as external networks.

## 2. Verify Elements and run the first backup

The backup script refuses the wrong UUID, a missing sentinel, a read-only mount,
or a repository outside Elements. If NTFS is read-only on the host, inspect host
logs and repair it from Windows where possible; do not force a read-write remount
of a dirty or hibernated filesystem. A restricted sandbox may show its bind as
read-only even when the host mount is healthy, so verify with host-level `findmnt`.
Run the backup and restore commands on Bumblebeam itself; an agent sandbox's mount
view is not a valid substitute for the host check.

After Elements is healthy and mounted read-write:

```sh
sudo apt-get update && sudo apt-get install restic
cp ops/backup/backup.env.example ops/backup/backup.env
install -d -m 700 ~/.config/restic
# Create long random passwords directly in the two files named by backup.env.
chmod 600 ops/backup/backup.env ~/.config/restic/bumblebeam-*.password
ops/backup/backup.sh --consistent --check
ops/backup/restore-test.sh local
ops/backup/retention.sh local --dry-run

# Run these only after the remote destination has been explicitly authorised.
ops/backup/backup.sh --consistent --check --copy-remote
ops/backup/restore-test.sh remote
ops/backup/retention.sh remote --dry-run
```

If sudo is unavailable, the scripts also discover the Ubuntu package extracted at
`.local/usr/bin/restic` and the current official rclone at `.local/usr/bin/rclone`;
`.local/` is ignored by Git.

The consistent run stops only stateful containers found running and restarts only
those containers. Its error/exit traps restart them if Restic fails. Verify service
health afterward.

## 3. OneDrive safeguards

`Dave-OneDrive:Backups/Bumblebeam/restic` is temporary replaceable storage, not
the authority for retention or repository integrity.

- Exclude `Backups/Bumblebeam/restic` from Ultra-Magners' desktop OneDrive sync.
- Do not expose it through a shortcut, shared folder, Files On-Demand selection,
  or any other desktop sync root.
- Access it only through Restic's rclone backend. Never run `rclone sync`, `copy`,
  `move`, or `purge` against repository internals, and never edit them manually.
- Protect the Microsoft account with a unique password, MFA, recovery methods,
  and login alerts. Store Restic recovery passwords separately in an offline
  password manager/recovery record.
- Folder exclusion reduces accidental local propagation only; it does not protect
  against Microsoft-account or Bumblebeam compromise.

Risks remain: host/account compromise, remote deletion, propagated corruption,
limited provider recovery, expired API tokens, quota exhaustion, and loss of the
Restic password.

If `Dave-OneDrive` reports `Unauthenticated`, reconnect it interactively and then
resume repository-aware transfer and verification:

```sh
rclone config reconnect Dave-OneDrive:
ops/backup/copy-remote.sh
restic -r rclone:Dave-OneDrive:Backups/Bumblebeam/restic \
  --password-file ops/backup/remote.password check --read-data-subset 1/10
ops/backup/restore-test.sh remote
```

## 4. Dedicated backup identity

Create a Microsoft identity used only for infrastructure backup, with separate
credentials, MFA/recovery details, adequate quota, and no desktop sync client.
Configure a separate rclone remote on Bumblebeam and a newly encrypted Restic
repository. Transfer snapshots with `restic copy`, then run full structure,
rotating sampled-data checks, and a test restore.

Keep Dave-OneDrive for at least two successful scheduled backups and one restore
test from the new identity. Record evidence before deliberate retirement. A later
append-only/object-lock backend is still required because a compromised host can
delete data using any continuously available OneDrive credential.

## 5. DNS and service recovery

On the GL.iNet DNS/DHCP server (`192.168.1.2`), maintain explicit host records for
`bumblebeam.home.arpa` (`192.168.1.15`), `vodafone.home.arpa` (`192.168.1.1`), and
`glinet.home.arpa` (`192.168.1.2`). Keep the wildcard
`*.svc.home.arpa → 192.168.1.15` for reverse-proxied applications and advertise
`svc.home.arpa` through DHCP. Do not create individual `*.home.arpa` service
records.

Recover in this order and record evidence in `docs/evidence/`:

1. Home Assistant: DNS, port 8123, proxy route, UI login, and one automation.
2. Plex: DNS, port 32400, proxy route, server ownership, and local playback.
3. n8n: DNS, port 5678/container health, local/public proxy routes, and a test webhook.
4. Gluetun/media: VPN public IP, DNS, tunnel health, then each dependent UI and a
   harmless end-to-end download/import test. **Imperative:** every test that originates
   on or traverses HOME_MEDIA must execute inside Gluetun's VPN namespace (or a
   container using `network_mode: container:gluetun`); never issue an outbound media,
   tracker, DNS, or download probe from the host, an agent sandbox, or another Docker
   network. See `docs/adr/0007-home-media-vpn-test-boundary.md`.

If HA works on `192.168.1.15:8123` but its Traefik route times out, test port 8123
from inside Traefik. Traefik reaches host-networked services through
`br-host-svc` as `172.22.0.10`; permit only that source to reach TCP 8123:

```sh
sudo ufw allow in on br-host-svc from 172.22.0.10 to any port 8123 proto tcp \
  comment 'Traefik to Home Assistant'
```

Do not permit Home Assistant through `br-gluetun` or `br-traefik`. Re-test both
canonical and compatibility hostnames afterward.

Example LAN-client checks:

```sh
getent ahostsv4 hass hass.svc.home.arpa bumblebeam.home.arpa
curl --fail --max-time 10 -I http://hass.svc.home.arpa
curl --fail --max-time 10 http://plex.svc.home.arpa/identity
curl --fail --max-time 10 -I http://n8n.svc.home.arpa
docker compose -f HomeAssistant/compose.yml ps
docker compose -f plex/compose.yml ps
docker compose -f n8n/compose.yml ps
docker compose -f Home_Media/compose.yml ps
```

## 6. Recurring operations

Install the supplied systemd units only after the manual initial backup succeeds.
Daily retention is 7 daily, 4 weekly, and 12 monthly. Monthly checks rotate through
one twelfth of local pack data and restore representative state from local and
remote repositories. Perform a quarterly isolated service-state restore drill and
review actual repository growth and quota headroom.
