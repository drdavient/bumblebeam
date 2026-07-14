# Data inventory and Git boundary

| Area | Classification | Git | Encrypted Restic | Notes |
|---|---|---:|---:|---|
| Compose, Dockerfiles, scripts, Traefik YAML | Declarative configuration | Yes | Yes | Validate before commit/deploy |
| Sanitised `.env.example` files | Declarative examples | Yes | Yes | Must contain no working credential |
| `.env`, HA `secrets.yaml`, n8n config, Plex preferences | Plaintext secrets/runtime configuration | No | Yes | Local mode 600 where feasible |
| HA SQLite/WAL and `.storage` | Stateful application data | No | Yes | Consistent snapshot preferred |
| n8n SQLite/config | Stateful application data | No | Yes | Consistent snapshot preferred |
| Plex databases and `Preferences.xml` | Stateful application data | No | Yes | Metadata/art/cache are excluded |
| Radarr/Sonarr/Prowlarr/Deluge/Gluetun config | Stateful application data | No | Yes | Logs, archives, cache excluded |
| Traefik `acme.json` | Certificate/account state | No | Yes | Must remain mode 600 |
| Logs, caches, thumbnails, transcodes, archives | Excluded/reproducible | No | No | Regenerated or low recovery value |
| Downloads and `/mnt/Elements/Video`, Music | Bulk media | No | No | Separate accepted risk/workstream |
| Restic repository internals | Encrypted backup state | No | N/A | Access only through Restic |

Before staging, run `git status --short --ignored` and the secret-location audit in
the stabilisation runbook. Runtime files already present in this working tree are
not made safe merely by being ignored; permissions and encrypted backup still
matter.
