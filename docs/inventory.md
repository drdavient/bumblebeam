# Data inventory and Git boundary

| Area | Classification | Git | Encrypted Restic | Notes |
|---|---|---:|---:|---|
| Compose, Dockerfiles, scripts, Traefik YAML | Declarative configuration | Yes | Yes | Validate before commit/deploy |
| Sanitised `.env.example` files | Declarative examples | Yes | Yes | Must contain no working credential |
| `.env`, HA `secrets.yaml`, n8n config, Plex preferences | Plaintext secrets/runtime configuration | No | Yes | Local mode 600 where feasible |
| HA SQLite/WAL and `.storage` | Stateful application data | No | Yes | Consistent snapshot preferred |
| n8n SQLite/config | Stateful application data | No | Yes | Consistent snapshot preferred |
| Seerr SQLite/config | Stateful application data | No | Yes | Family request history, application settings, and Plex integration state |
| Plex databases and `Preferences.xml` | Stateful application data | No | Yes | Metadata/art/cache are excluded |
| Radarr/Sonarr/Prowlarr/Deluge/Gluetun/Shelfarr/Audiobookshelf config | Stateful application data | No | Yes | Logs, archives, cache excluded |
| Traefik `acme.json` | Certificate/account state | No | Yes | Must remain mode 600 |
| Zigbee2MQTT runtime (`zigbee/zigbee2mqtt/data/`: `configuration.yaml` with network key, `database.db`, `coordinator_backup.json`) | Stateful application data | No | Yes | Losing it loses the Zigbee network identity — every device must re-pair; consistent snapshot preferred |
| Mosquitto retained messages (`zigbee_mosquitto-data` named volume) | Excluded/reproducible | No | No | Retained topics (e.g. `pomodoro/dnd/state`) regenerate on the next state change |
| Mosquitto `config/passwd` (hashed broker credentials) | Excluded/reproducible | No | No | Root-owned; regenerate with `mosquitto_passwd` from client plaintext credentials, which are in the backup (Z2M `configuration.yaml`, HA `.storage`) or on the client (Windows agent) |
| App shelf catalog app + `catalog.json` + `fetch-seed-apks.sh` | Declarative configuration | Yes | Yes | Seed APK set is reproducible from the fetch script |
| App shelf `apks/*.apk` (seed) | Excluded/reproducible | No | Yes | Re-downloadable via `fetch-seed-apks.sh` (SHA-256 pinned) |
| App shelf `apks/*.apk` (owner-supplied, e.g. owned games) + Filebrowser DB | Stateful/bulk application data | No | Yes | Owner-supplied purchases; never fetched from mirrors, never committed |
| Logs, caches, thumbnails, transcodes, archives | Excluded/reproducible | No | No | Regenerated or low recovery value |
| Downloads and media libraries (`/mnt/Elements/media/`; legacy `/mnt/Elements/Video`, `Music`) | Bulk media | No | No | Separate accepted risk/workstream; migrate by the staged plan in ADR 0010 |
| Removable SD card (`/mnt/sdcard`) | Transient removable media | No | No | systemd automount via `/etc/fstab` (`nofail`, uid/gid 1000, 60 s idle unmount); first partition of any card in the reader (`/dev/mmcblk0p1`) mounts on access |
| Restic repository internals | Encrypted backup state | No | N/A | Access only through Restic |

Before staging, run `git status --short --ignored` and the secret-location audit in
the stabilisation runbook. Runtime files already present in this working tree are
not made safe merely by being ignored; permissions and encrypted backup still
matter.
