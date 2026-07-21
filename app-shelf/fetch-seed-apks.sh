#!/usr/bin/env bash
# Download the seed set of free / open-source APKs into ./apks, verifying each
# SHA-256 against the F-Droid index. Re-runnable: skips files already present and
# valid. The APK binaries are NOT committed to Git (reproducible from here) — this
# script is the source of truth for the seed shelf.
#
# All titles are freely redistributable (F-Droid main repo). VLC is the requested
# media player; the rest are lightweight, age-appropriate games/tools that install
# on Fire OS 5 (5th-gen Fire, Android 5.1 / API 22).
#
# ABI matters: the Fire 7 5th-gen is 32-bit ARM (armeabi-v7a). VLC ships a separate
# APK per architecture, so we pin the armeabi-v7a build (version code ...105); the
# arm64/x86 builds report "App not installed" on this device. The games are universal
# (all ABIs in one APK) or pure-Java.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/apks"
BASE="https://f-droid.org/repo"
mkdir -p "$DIR"

# apkName  sha256
APKS=(
  "org.videolan.vlc_13070105.apk                       0c316a06fdb44efbdaa9ba7f39c7fd7d5b4efc0e61b2b7a94a008e7625f699cd"
  "com.gitlab.ardash.appleflinger.android_1006001.apk  ed44fd844d7ce7afa84f7902b68233b08a6b82c137de117bcf6ad19c1fa4ef6f"
  "com.agateau.tinywheels.android_33.apk               61a50936e728518ce90e7191f8454a98ff24a80b866fa58292a0b474d2dabcd1"
  "com.dozingcatsoftware.bouncy_43.apk                 ffda0d9cb0b1b2aa58be9559dda891c4fa24391bc481d297a8e3d96c31f62721"
  "se.tube42.kidsmem.android_17.apk                    fe53a43347708510218c46239bf0a68daf1333dfffbb0cfca1fe3de1849c8b28"
  "dev.alexjyong.babbypaint_9.apk                      cd1433dfdca577233c07743188339a6f43f68afafd81e6d36c7feb0e5182706b"
)

for row in "${APKS[@]}"; do
  read -r name sha <<<"$row"
  dest="$DIR/$name"
  if [[ -f "$dest" ]] && echo "$sha  $dest" | sha256sum -c --status; then
    echo "ok (cached)   $name"
    continue
  fi
  echo "downloading   $name"
  curl -fSL --retry 3 -o "$dest" "$BASE/$name"
  echo "$sha  $dest" | sha256sum -c --status || { echo "CHECKSUM FAILED: $name" >&2; rm -f "$dest"; exit 1; }
  echo "verified      $name"
done

echo "Seed shelf ready in $DIR"
