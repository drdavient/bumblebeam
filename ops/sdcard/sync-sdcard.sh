#!/usr/bin/env bash
# sync-sdcard.sh — mirror this card's Plex collection ("SD Card <N>") onto the SD card.
#
# Curation happens in Plex: put movies/shows in a collection named "SD Card 1" or
# "SD Card 2" (in any movie/show section — the same name can exist in both Movies
# and TV). The card itself records which selection it carries via a .sdcard-id
# marker file stamped at first use (--init N), so plain `sync-sdcard.sh` always
# syncs the right content for whichever card is inserted.
#
# Deletion is scoped: only files under the top-level directories the manifest
# uses (Movies/, TV/) are ever removed, so anything else on the card is safe.
#
# Usage:
#   sync-sdcard.sh              sync the inserted card per its marker
#   sync-sdcard.sh --init 2     stamp the inserted card as card 2, then sync
#   sync-sdcard.sh --dry-run    show what would change without writing

set -euo pipefail

MOUNT=/mnt/sdcard
SRC=/mnt/Elements/Video
PLEX=http://localhost:32400
PREFS="/home/drdavient/docker/plex/PMS/Library/Application Support/Plex Media Server/Preferences.xml"
MARKER=".sdcard-id"
MANIFEST="sdcard-manifest.txt"

die() { echo "ERROR: $*" >&2; exit 1; }

DRY=0 INIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --init) shift; INIT="${1:-}"; [[ "$INIT" =~ ^[0-9]+$ ]] || die "--init needs a card number" ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

# Touch the path so systemd automount mounts an inserted card, then verify.
ls "$MOUNT" >/dev/null 2>&1 || true
mountpoint -q "$MOUNT" || die "no SD card mounted at $MOUNT"

if [ -n "$INIT" ]; then
  echo "$INIT" > "$MOUNT/$MARKER"
fi
[ -f "$MOUNT/$MARKER" ] || die "card has no $MARKER — run with --init <1|2> to stamp it"
CARD=$(tr -cd '0-9' < "$MOUNT/$MARKER")
[ -n "$CARD" ] || die "unreadable card id in $MOUNT/$MARKER"
COLLECTION="SD Card $CARD"
echo "Card $CARD inserted — syncing Plex collection '$COLLECTION'"

TOKEN=$(sed -n 's/.*PlexOnlineToken="\([^"]*\)".*/\1/p' "$PREFS")
[ -n "$TOKEN" ] || die "could not read Plex token from Preferences.xml"
plex() {  # GET a Plex API path; the token stays out of argv and logs
  curl -sf --max-time 30 -K <(printf 'header = "X-Plex-Token: %s"\nheader = "Accept: application/json"\n' "$TOKEN") "$PLEX$1"
}

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
: > "$WORK/files"

found=0
for sec in $(plex /library/sections | jq -r '.MediaContainer.Directory[] | select(.type=="movie" or .type=="show") | .key'); do
  for col in $(plex "/library/sections/$sec/collections" | jq -r --arg t "$COLLECTION" '.MediaContainer.Metadata[]? | select(.title==$t) | .ratingKey'); do
    found=1
    plex "/library/collections/$col/children" | jq -r '.MediaContainer.Metadata[]? | "\(.ratingKey)\t\(.type)"' > "$WORK/children"
    while IFS=$'\t' read -r rk type; do
      case "$type" in
        movie|episode) plex "/library/metadata/$rk" | jq -r '.MediaContainer.Metadata[].Media[]?.Part[]?.file // empty' ;;
        show|season)   plex "/library/metadata/$rk/allLeaves" | jq -r '.MediaContainer.Metadata[]?.Media[]?.Part[]?.file // empty' ;;
      esac
    done < "$WORK/children" >> "$WORK/files"
  done
done
[ "$found" -eq 1 ] || die "no collection named '$COLLECTION' in Plex — create it and add items"

# Container path /media/... -> path relative to $SRC on the host.
sort -u "$WORK/files" | while read -r f; do
  rel="${f#/media/}"
  if [ "$rel" = "$f" ]; then echo "WARN: skipping non-/media path: $f" >&2; continue; fi
  if [ ! -f "$SRC/$rel" ]; then echo "WARN: missing on host, skipping: $rel" >&2; continue; fi
  echo "$rel"
done > "$WORK/manifest"
COUNT=$(wc -l < "$WORK/manifest")
[ "$COUNT" -gt 0 ] || die "collection '$COLLECTION' resolved to zero files"
TOTAL=$(cd "$SRC" && tr '\n' '\0' < "$WORK/manifest" | du -ch --files0-from=- 2>/dev/null | tail -1 | cut -f1)
echo "$COUNT files, $TOTAL total"

RSYNC_FLAGS=(-rt --modify-window=2 --partial --files-from="$WORK/manifest")
[ "$DRY" -eq 1 ] && RSYNC_FLAGS+=(--dry-run -v)
rsync "${RSYNC_FLAGS[@]}" "$SRC/" "$MOUNT/"

# Remove card files the manifest no longer lists (scoped to manifest top dirs).
sort "$WORK/manifest" > "$WORK/sorted"
cut -d/ -f1 "$WORK/manifest" | sort -u | while read -r top; do
  [ -d "$MOUNT/$top" ] || continue
  (cd "$MOUNT" && find "$top" -type f)
done | sort > "$WORK/oncard"
comm -23 "$WORK/oncard" "$WORK/sorted" > "$WORK/stale"
if [ -s "$WORK/stale" ]; then
  echo "Removing $(wc -l < "$WORK/stale") file(s) no longer in the collection:"
  sed 's/^/  - /' "$WORK/stale"
  if [ "$DRY" -eq 0 ]; then
    while read -r f; do rm -f -- "$MOUNT/$f"; done < "$WORK/stale"
    find "$MOUNT" -mindepth 1 -type d -empty -delete
  fi
fi

if [ "$DRY" -eq 0 ]; then
  cp "$WORK/manifest" "$MOUNT/$MANIFEST"
  sync
fi
df -h "$MOUNT" | tail -1 | awk '{print "Card usage: "$3" used, "$4" free ("$5")"}'
echo "Done."
