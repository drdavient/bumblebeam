# app-shelf

Self-hosted APK catalog for sideloading apps onto LAN devices — built for the
household's Amazon Fire 7 (5th-gen) tablets, which run Fire OS 5 (Android 5.1 / API 22)
with no Google Play.

- **Catalog** (`apps.svc.home.arpa`) — read-only, touch-friendly download page for the
  tablets. Auto-reads each APK's name/version/min-SDK and flags Fire OS 5 compatibility.
- **Manager** (`appfiles.svc.home.arpa`) — Filebrowser; the parent uploads/removes APKs.

See `docs/runbooks/fire-tablet-sideload.md` for tablet setup and how to add apps you
own, and `docs/adr/0011-lan-app-shelf-for-sideloading.md` for the design and the
licensing boundary (only redistributable APKs are hosted from Git; paid titles you own
are owner-supplied, never fetched from mirrors).

## Deploy

```bash
./fetch-seed-apks.sh          # download + SHA-256-verify the free seed apps into ./apks
docker compose up -d --build
```

## Layout

```
app-shelf/
  catalog/            Flask + pyaxmlparser image (the catalog page)
  apks/               served APK directory (binaries Git-ignored; catalog.json tracked)
    catalog.json      optional per-file {label, note} overrides
  filebrowser/        Filebrowser runtime state (Git-ignored)
  fetch-seed-apks.sh  reproducible seed download with checksum verification
  compose.yml
```

The APK binaries are not committed: the seed set is reproducible via the fetch script,
and owner-supplied APKs live only in the runtime tree / encrypted backup.
