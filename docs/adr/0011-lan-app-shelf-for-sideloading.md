# ADR 0011: LAN app shelf for sideloading APKs to Fire tablets

- Status: accepted
- Date: 2026-07-20

## Context

The household has Amazon Fire 7 tablets (5th generation) for children aged 5, 5,
and 7. Fire OS 5 is Android 5.1 (API 22) and ships without Google Play, so apps
arrive by sideloading `.apk` files. We want a simple, self-hosted way to browse and
download vetted apps over the LAN, plus a lightweight interface to curate the set.

## Decision

Run a small **app shelf** on Bumblebeam: a read-only catalog page for the tablets and
a separate file manager for the parent. It follows the standalone Traefik-attached
Compose pattern (as with Audiobookshelf).

- `app-shelf` (custom Flask + `pyaxmlparser` image) scans a directory of APKs, reads
  each one's label/version/`minSdkVersion`, and renders a touch-friendly download page
  at `apps.svc.home.arpa`. It flags whether each app installs on Fire OS 5
  (`minSdkVersion <= 22`). Serving uses the `application/vnd.android.package-archive`
  MIME type so Silk offers "open to install".
- `app-shelf-files` (Filebrowser) exposes upload/delete over `appfiles.svc.home.arpa`,
  writing into the same APK directory. New files appear in the catalog automatically.

Both are HTTP on the LAN `web` entrypoint, no host ports, joined to `traefik-net`.
Names resolve via the existing `*.svc.home.arpa` wildcard — no new DNS records.

## Licensing boundary

This is the load-bearing constraint and the reason the sourcing is split:

- **Only freely redistributable APKs are hosted from Git-tracked, reproducible
  sources.** The seed set (VLC and several open-source F-Droid games) is downloaded
  and SHA-256-verified by `app-shelf/fetch-seed-apks.sh` against the F-Droid index.
  The binaries themselves are not committed (reproducible from the script).
- **Paid or proprietary titles are never fetched from third-party APK mirrors and
  never committed.** When the household owns a paid app (e.g. Minecraft: Pocket
  Edition, Angry Birds) the owner supplies the APK from an authorised channel — the
  Amazon Appstore, Google Play sideloaded onto a Fire, or extraction from a device
  where the household already owns it — and drops it into the runtime `apks/`
  directory. See `docs/runbooks/fire-tablet-sideload.md`. Serving one's own purchases
  to one's own family devices is format-shifting; re-hosting mirror downloads is not,
  and we do not do it.

## Consequences

- The APK directory is runtime/bulk data: `app-shelf/apks/*.apk` and the Filebrowser
  database are Git-ignored and classified in `docs/inventory.md`. The seed set is
  reproducible; owner-supplied APKs are the owner's to re-provide (kept in the
  encrypted backup once present).
- Compatibility is best-effort: `minSdkVersion <= 22` is the install gate, but not a
  guarantee an old device runs a title well. Fire 5th-gen hardware is weak (1 GB RAM),
  so the seed set favours lightweight 2D apps.
- Filebrowser initialises an `admin` user with a random password (printed to its
  container log on first run). It is LAN-only; change the password on first login.
