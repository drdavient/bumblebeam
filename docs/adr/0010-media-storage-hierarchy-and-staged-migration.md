# ADR 0010: Elements media storage hierarchy and staged migration

- Status: accepted
- Date: 2026-07-16

## Decision

Adopt `/mnt/Elements/media/` as the canonical root for media libraries. The first
cutover is audiobooks:

```text
/mnt/Elements/media/audiobooks
```

Audiobookshelf mounts that directory read-only at `/audiobooks`; Shelfarr mounts the
same directory read-write at `/audiobooks` for completed imports. Existing `Video`,
`Music`, and `Downloads` roots remain live until their individual cutovers are planned
and verified. This ADR does not authorise a bulk move or a change to their paths.

The intended end-state is:

```text
/mnt/Elements/media/
  audiobooks/
  music/
  video/
    movies/
    tv/
  downloads/
    transmission/
```

The end-state layout is a target, not a requirement to move every category at once.
Container-visible paths should remain stable wherever practical: `/audiobooks`,
`/music`, `/media`, `/movies`, `/tv`, and `/downloads`. Changing the host-side bind
source while preserving the container target avoids unnecessary application database
or library-path edits.

## When a migration is sane

Perform one category at a time, only when all of the following are true:

1. The Elements mount is the expected read-write filesystem and its sentinel exists.
2. A current encrypted Restic snapshot exists, with a successful representative
   restore; take another snapshot immediately before the move if the media cannot be
   recreated.
3. The category has no active import, transcoding, or library scan. For downloads,
   also confirm that no torrent must continue seeding from its current path.
4. The planned service stop/start order, exact old and new paths, rollback path, and
   post-cutover playback/import checks are recorded before changing data.

The audiobook cutover is complete only after Audiobookshelf scans the new root,
Shelfarr imports a permitted test title into it, and a household user can play it.
Do not begin the broader migration until those checks remain healthy through a normal
backup cycle.

## Per-stack migration work

| Component | Change when its category moves | Verification |
|---|---|---|
| Audiobookshelf | Already points at `media/audiobooks`; keep `/audiobooks` read-only. | Library scan and playback from the new root. |
| Shelfarr | Already writes to `media/audiobooks`; keep the same `/audiobooks` target. Configure the completed-download path consistently with Deluge. | Request, VPN-routed download/import, then Audiobookshelf scan. |
| Deluge | If downloads move, change its host bind to `media/downloads/transmission` while retaining `/downloads`; move only with no active/seeding torrents, or update Deluge's saved paths deliberately. | Existing torrents resume (if retained) and a permitted new download completes through Gluetun. |
| Sonarr and Radarr | Change host binds to `media/video/tv` and `media/video/movies`, retaining `/tv` and `/movies`; change their `/downloads` bind at the same time as Deluge if downloads move. | Root folders stay valid; a permitted import completes through Gluetun. |
| Plex | Prefer changing host bind sources to `media/video` → `/media` and `media/music` → `/music`, keeping Plex's container paths stable. | Existing libraries remain mapped, scan finds no duplicate paths, and local playback succeeds. |
| Prowlarr, FlareSolverr, Gluetun, Seerr, Traefik | No library-path changes. Recheck integrations after the dependent services are healthy. | Existing UI/integration checks pass. |
| Mount watcher and Plex helper scripts | After the video cutover, replace their hard-coded legacy `Video` paths with `media/video`. | Boot/mount guard and helper dry runs use the new root. |
| Backup and inventory | Keep runtime application state in Restic; media remains bulk data outside Git and the existing backup scope unless its policy changes separately. | Backup validation still passes; inventory remains accurate. |

## Execution and rollback

For a category, stop only the services that write or index it; copy/move with an
attribute-preserving, resumable host-side tool; verify file counts and representative
hashes; then change the relevant Compose binds and deploy from the canonical checkout.
Keep the old tree intact until the acceptance checks and a backup complete. Rollback is
to stop the changed services, restore their prior bind sources, and start them again;
do not attempt a database path rewrite as the first rollback action.

All HOME_MEDIA download, metadata, indexer, import, and connectivity verification
continues to run through Gluetun under ADR 0007. LAN playback and Traefik route checks
remain ingress-only tests.

## Consequences

- New media categories have one predictable home without forcing a risky one-shot
  reorganisation of existing libraries.
- Stable container paths minimise Plex and *arr database churn and make rollback
  mechanical.
- The migration has an explicit gate for active torrents and recoverability rather
  than relying on filesystem renames during normal service operation.
