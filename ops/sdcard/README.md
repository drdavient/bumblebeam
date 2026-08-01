# SD card media sync

Kids' media for the Kindle Fire (VLC reads the card directly — no Plex client
needed). Two 128GB exFAT cards carry different selections; each selection is a
Plex **collection** named `SD Card 1` / `SD Card 2` (the same name exists in
both the Movies and TV Shows sections and the union is synced).

## Workflow

1. **Curate in Plex**: add/remove movies or whole shows in the `SD Card <N>`
   collections (Edit → Tags → Collection, or multi-select → Add to Collection).
2. **Insert a card** into Bumblebeam's reader. udev triggers
   `sdcard-sync.service`, which mounts the card (systemd automount at
   `/mnt/sdcard`, see `/etc/fstab`) and runs `sync-sdcard.sh`.
3. The script reads the card's `.sdcard-id` marker (stamped once with
   `--init <N>`), resolves that collection's episodes/movies via the Plex API,
   rsyncs new/changed files, and deletes files dropped from the collection.
   Progress: `journalctl -u sdcard-sync -f`.
4. Wait for idle (the automount unmounts after 60s idle) and pull the card.

Manual run: `./sync-sdcard.sh [--dry-run] [--init <N>]`.

## Notes

- Deletion is scoped to the top-level dirs the manifest uses (`Movies/`, `TV/`);
  anything else on the card (tablet files, `.sdcard-id`, manifest) is untouched.
- The Plex token is read at runtime from the server's own `Preferences.xml` and
  never appears in argv, logs, or Git.
- Path mapping mirrors the Plex container mount: `/media/…` →
  `/mnt/Elements/Video/…`.
- Most content is 720p H.264, ideal for the Fire 7's 1024×600 screen; no
  transcoding is done. If a title won't play in VLC, prefer swapping in a
  different encode over adding a transcode stage.

## Tablet setup (Kindle Fire 7, VLC)

- VLC → Settings → **Directories**: tick the SD card storage root, or the Video
  tab never indexes the card (Browse works regardless). If the library goes
  stale after a card swap, Settings → Advanced → Clear media database.
- Keep **"Install supported apps on SD card" off** (Fire Settings → Storage):
  apps on a swapped-out card break. Downloads on card are harmless.
- Always **Safely remove** (Fire Settings → Storage) before popping the card.

## Phone targets (Syncthing)

The same script also feeds phones over WiFi: `--dest DIR --collection NAME`
syncs a named collection into a directory instead of a card (no marker, no
mount logic; same pretty names, embedded art, scoped deletion). The
directories live under `syncthing/data/phones/<name>` and are shared by the
Syncthing container (`syncthing/compose.yml`, UI at
`http://syncthing.svc.home.arpa`) as **send-only** folders, so phone-side
deletions never propagate back and get re-filled on the next sync.

Current target: Winter's OnePlus 6 — collection "Phone - Winter", folder id
`winter-phone`, refreshed daily at 04:30 by drdavient's crontab. VLC on the
phone indexes the synced folder.

Phone-side pairing (once): install Syncthing (F-Droid/Play) → menu → Show
device ID on the server UI → add remote device on the phone with address
`tcp://192.168.1.15:22000` (the container announces a bridge IP, so local
discovery alone won't find it) → accept the share; set the folder to
receive-only on the phone.

## Install (once per host)

```sh
sudo cp systemd/sdcard-sync.service /etc/systemd/system/
sudo cp udev/99-sdcard-sync.rules /etc/udev/rules.d/
sudo systemctl daemon-reload && sudo udevadm control --reload
```
