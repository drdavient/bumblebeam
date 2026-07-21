# Runbook: sideloading apps onto Fire 5th-gen tablets

Covers the Bumblebeam **app shelf** and how to get apps — including paid titles you
already own — onto an Amazon Fire 7 (5th generation, Fire OS 5 / Android 5.1 / API 22)
that has no Google Play. See `docs/adr/0011-lan-app-shelf-for-sideloading.md`.

## Services

| What | URL | For |
|---|---|---|
| App catalog (download + install) | `http://apps.svc.home.arpa/` (bare `http://apps/` works on the LAN) | The tablets |
| File manager (add/remove APKs) | `http://appfiles.svc.home.arpa/` | The parent |

Stack lives at `app-shelf/`. Deploy from the canonical checkout:

```bash
cd app-shelf
./fetch-seed-apks.sh          # download + verify the free seed apps into ./apks
docker compose up -d --build
```

## One-time tablet setup (allow installs)

1. On the Fire: **Settings → Security & Privacy → Apps from Unknown Sources** →
   enable (older builds) or **Install unknown apps → Silk Browser → Allow**.
2. Open Silk and go to `http://apps/` (or `http://apps.svc.home.arpa/`).

## Installing an app on the tablet

1. Tap **Get** on the catalog. The APK downloads.
2. Open the notification (or Silk's Downloads) and tap the file → **Install**.
3. A **Fire 5 OK** badge means the app's `minSdkVersion` is ≤ 22 and will install.
   *needs newer Fire* means it will refuse on a 5th-gen device.

## "App not installed" during install

Almost always a **CPU architecture (ABI) mismatch**: the Fire 7 5th-gen is 32-bit ARM
(`armeabi-v7a`), and an APK built only for arm64/x86 refuses to install here even though
it downloaded fine. Some apps (notably VLC) ship a separate APK per architecture — pick
the `armeabi-v7a` one. The catalog guards against this: it reads each APK's bundled CPU
libraries and shows **wrong CPU (needs 32-bit ARM)** instead of **Fire 5 OK** when an app
won't run. Other causes: not enough free storage, or a leftover half-download — delete
the old file from Silk's Downloads and tap **Get** again.

## Curating the shelf (parent)

- Add: open `http://appfiles.svc.home.arpa/`, sign in (see credentials below), and
  **upload** an `.apk`. It appears in the catalog within a refresh.
- Friendly names/notes: edit `app-shelf/apks/catalog.json`
  (`{"file.apk": {"label": "...", "note": "..."}}`).
- Remove: delete the file in Filebrowser.
- **Filebrowser credentials:** on first run it prints
  `User 'admin' initialized with randomly generated password: …` to its log:
  `docker logs app-shelf-files | grep password`. Log in and change it (LAN-only).

## Paid titles you already own (Minecraft: Pocket Edition, Angry Birds)

The shelf will serve these once you place the APK in `apks/`, but **only obtain them
from an authorised source** — do not download paid apps from APK-mirror sites (unknown
provenance = malware risk on a child's device, and it is unauthorised redistribution).
Three legitimate routes, best-first for a Fire 5:

1. **Amazon Appstore (simplest — already on the tablet).** The Appstore is
   pre-installed on every Fire. Search for the title; if it is listed and you own/buy
   it there, install directly — the Appstore serves the last version compatible with
   Fire OS 5 automatically. Minecraft is on the Amazon Appstore; some Angry Birds
   titles are too. No sideloading needed. (An Amazon purchase is a separate licence
   from a Google Play one.)

2. **Sideload Google Play onto the Fire, then install what you own.** Fire OS 5 can run
   the Google Play stack. Install, in order, the four packages **matched to Fire OS 5 /
   Android 5.1 (arm)** — Google Account Manager, Google Services Framework, Google Play
   Services, Google Play Store — from a reputable APK host (APKMirror, run by Android
   Police, is the usual choice; it does not host paid apps, only these free framework
   ones). Reboot, sign in with your Google account, then install Minecraft/Angry Birds
   from Play. Play delivers the newest version that still supports API 22, which is
   exactly the "old version that works" on this device. You can then stop here (Play
   keeps them updated) or extract the installed APK (route 3) to serve from the shelf.

3. **Extract from a device where you already own it.** On an Android phone/tablet
   signed in to the account that owns the app, install an "APK extractor" app (or use
   `adb`), export the installed APK, and upload it to the shelf via Filebrowser. This
   is format-shifting your own purchase. The extracted version must support API 22 to
   install on the Fire — if the phone's build is too new, use route 2 on the Fire
   instead so Play picks the compatible version.

> Angry Birds note: Rovio delisted the original "Classic" games from Google Play. The
> Amazon Appstore or an extracted copy of a version you already own are the realistic
> routes for a 5th-gen Fire; the current Play titles need newer Android.

## Playing library media in VLC over SMB

For watching the media library on a Fire tablet, SMB is saner than Plex DLNA: VLC
plays files directly, and it does not depend on SSDP multicast (which the WiFi tends to
drop between wireless and wired clients — the usual reason a DLNA server never appears).

**Boundary note:** Samba runs as a **host service on Bumblebeam** (`/etc/samba/smb.conf`,
`smbd`/`nmbd`), *not* as a container in this repo. These steps are host configuration and
are recorded here for reproducibility only — there is no Compose file to change. SMB1 is
disabled (correct); VLC 3.7 uses SMB2/3.

The pre-existing `[Elements]` share is read-write and limited to `drdavient` — do not put
those credentials on a child's device. Instead add a **dedicated read-only user** and a
read-only share:

```bash
# 1. Login-less Unix account for SMB auth (files are still read as drdavient via force user)
sudo useradd --system --no-create-home --shell /usr/sbin/nologin familytv

# 2. Set + enable its Samba password (you choose it; typed once per tablet)
sudo smbpasswd -a familytv
sudo smbpasswd -e familytv

# 3. Append the read-only share
sudo tee -a /etc/samba/smb.conf >/dev/null <<'EOF'

[Media]
    path = /mnt/Elements
    browseable = yes
    read only = yes
    valid users = familytv
    force user = drdavient
EOF

# 4. Validate and reload (does not drop existing sessions)
sudo testparm -s && sudo smbcontrol all reload-config

# 5. Verify familytv sees the share
smbclient -L localhost -U familytv
```

On the tablet: VLC → **≡ → Browsing → Local Network → bumblebeam → Media**, log in as
`familytv` with that password (workgroup `WORKGROUP` or blank). If the server name does
not appear, add it by address: `smb://192.168.1.15/Media`. Access is read-only, so
nothing on the library can be changed or deleted from the tablet. To narrow what is
exposed, point `path` at a subfolder (e.g. `/mnt/Elements/Video`) instead of the drive
root.

## Seed apps (free / open-source, hosted from Git-tracked sources)

Downloaded and SHA-256-verified by `app-shelf/fetch-seed-apks.sh`:

| App | What | Ages |
|---|---|---|
| VLC | Video/music player, plays almost anything | all |
| Apple Flinger | Slingshot physics (Angry Birds style) | 5–7 |
| Pixel Wheels | Top-down kart racing | 5–7 |
| Vector Pinball | Simple pinball | 5–7 |
| Candy Memory | Match-the-pairs memory game | 5 |
| BabbyPaint | Finger-painting, no menus | 5 |

To add more free games: find them at `https://f-droid.org` (pick a version whose
"minimum Android" is 5.1 or lower), add the filename + SHA-256 to
`fetch-seed-apks.sh`, and re-run it — or just upload the APK via Filebrowser.
