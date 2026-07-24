#!/usr/bin/env bash
# sync-sdcard.sh — mirror this card's Plex collection ("SD Card <N>") onto the SD card.
#
# Curation happens in Plex: put movies/shows in a collection named "SD Card 1" or
# "SD Card 2" (in any movie/show section — the same name can exist in both Movies
# and TV). The card itself records which selection it carries via a .sdcard-id
# marker file stamped at first use (--init N), so plain `sync-sdcard.sh` always
# syncs the right content for whichever card is inserted.
#
# Files are laid out on the card under PRETTY names built from Plex metadata —
#   Movies/Cars (2006).mkv
#   TV/Bluey/Season 01/Bluey - S01E01 - Magic Xylophone.mkv
# — so a plain file browser (e.g. VLC on a tablet) reads like a shelf. Episodes
# Plex couldn't parse (index 0/duplicated) fall back to their original basename
# inside the show folder. A card synced under the old source-name layout is
# migrated by renaming in place (size-matched), not recopied.
#
# Deletion is scoped to Movies/ and TV/, so anything else on the card is safe.
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
san() { printf '%s' "$1" | tr '\\/:*?"<>|' '-' | sed 's/[. ]*$//'; }  # exFAT-safe

DRY=0 INIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --init) shift; INIT="${1:-}"; [[ "$INIT" =~ ^[0-9]+$ ]] || die "--init needs a card number" ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

# Never run two syncs at once (e.g. udev firing on a reinsertion mid-sync).
exec 9>/tmp/sdcard-sync.lock
flock -n 9 || die "another sync is already running"

# Touch the path so systemd automount mounts an inserted card. Retry for up to
# 30s: when udev triggers us on insertion, the partition may not be ready yet.
for _ in $(seq 1 15); do
  ls "$MOUNT" >/dev/null 2>&1 || true
  mountpoint -q "$MOUNT" && break
  sleep 2
done
mountpoint -q "$MOUNT" || die "no SD card mounted at $MOUNT (waited 30s)"

if [ -n "$INIT" ] && [ "$DRY" -eq 0 ]; then
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
: > "$WORK/map"   # lines: dest<TAB>source-path-relative-to-$SRC
declare -A SEEN

emit() { # <dest> <container-file-path>  (falls back on collisions/bad paths)
  local dest="$1" f="$2" rel
  rel="${f#/media/}"
  if [ "$rel" = "$f" ]; then echo "WARN: non-/media path skipped: $f" >&2; return; fi
  if [ ! -f "$SRC/$rel" ]; then echo "WARN: missing on host, skipped: $rel" >&2; return; fi
  if [ -n "${SEEN[$dest]:-}" ]; then dest="${dest%/*}/$(basename "$rel")"; fi
  if [ -n "${SEEN[$dest]:-}" ]; then echo "WARN: duplicate dest skipped: $dest" >&2; return; fi
  SEEN[$dest]=1
  printf '%s\t%s\n' "$dest" "$rel" >> "$WORK/map"
}

found=0
for sec in $(plex /library/sections | jq -r '.MediaContainer.Directory[] | select(.type=="movie" or .type=="show") | .key'); do
  for col in $(plex "/library/sections/$sec/collections" | jq -r --arg t "$COLLECTION" '.MediaContainer.Metadata[]? | select(.title==$t) | .ratingKey'); do
    found=1
    plex "/library/collections/$col/children" \
      | jq -r '.MediaContainer.Metadata[]? | [.ratingKey, .type, (.title//"Unknown"), (.year//"" | tostring), (.parentTitle//"")] | @tsv' > "$WORK/children"
    while IFS=$'\t' read -r rk type title year ptitle; do
      case "$type" in
        movie)
          local_title=$(san "$title"); [ -n "$year" ] && local_title="$local_title ($year)"
          n=0
          while IFS= read -r f; do
            [ -n "$f" ] || continue
            n=$((n+1)); ext="${f##*.}"
            suffix=""; [ "$n" -gt 1 ] && suffix=" - pt$n"
            emit "Movies/$local_title$suffix.$ext" "$f"
          done < <(plex "/library/metadata/$rk" | jq -r '.MediaContainer.Metadata[].Media[]?.Part[]?.file // empty')
          ;;
        show)
          show=$(san "$title")
          while IFS=$'\t' read -r snum enum etitle f; do
            [ -n "$f" ] || continue
            ext="${f##*.}"
            if [ "${enum:-0}" -gt 0 ] 2>/dev/null; then
              ep=$(printf 'S%02dE%02d' "$snum" "$enum")
              name="$show - $ep"; [ -n "$etitle" ] && name="$name - $(san "$etitle")"
              emit "TV/$show/Season $(printf '%02d' "$snum")/$name.$ext" "$f"
            else
              emit "TV/$show/$(basename "$f")" "$f"
            fi
          done < <(plex "/library/metadata/$rk/allLeaves" \
            | jq -r '.MediaContainer.Metadata[]? | . as $m | $m.Media[]?.Part[]? | [($m.parentIndex//0), ($m.index//0), ($m.title//""), .file] | @tsv')
          ;;
        season)  # a single season added to the collection; episodes are its children
          show=$(san "${ptitle:-$title}")
          while IFS=$'\t' read -r snum enum etitle f; do
            [ -n "$f" ] || continue
            ext="${f##*.}"
            if [ "${enum:-0}" -gt 0 ] 2>/dev/null; then
              ep=$(printf 'S%02dE%02d' "$snum" "$enum")
              name="$show - $ep"; [ -n "$etitle" ] && name="$name - $(san "$etitle")"
              emit "TV/$show/Season $(printf '%02d' "$snum")/$name.$ext" "$f"
            else
              emit "TV/$show/$(basename "$f")" "$f"
            fi
          done < <(plex "/library/metadata/$rk/children" \
            | jq -r '.MediaContainer.Metadata[]? | . as $m | $m.Media[]?.Part[]? | [($m.parentIndex//0), ($m.index//0), ($m.title//""), .file] | @tsv')
          ;;
      esac
    done < "$WORK/children"
  done
done
[ "$found" -eq 1 ] || die "no collection named '$COLLECTION' in Plex — create it and add items"

COUNT=$(wc -l < "$WORK/map")
[ "$COUNT" -gt 0 ] || die "collection '$COLLECTION' resolved to zero files"
TOTAL=$(cd "$SRC" && cut -f2 "$WORK/map" | tr '\n' '\0' | du -ch --files0-from=- 2>/dev/null | tail -1 | cut -f1)
echo "$COUNT files, $TOTAL total"

copied=0 renamed=0
while IFS=$'\t' read -r dest rel; do
  s="$SRC/$rel"; d="$MOUNT/$dest"
  ssz=$(stat -c%s "$s")
  [ -f "$d" ] && [ "$(stat -c%s "$d")" = "$ssz" ] && continue
  legacy="$MOUNT/$rel"
  if [ "$legacy" != "$d" ] && [ -f "$legacy" ] && [ "$(stat -c%s "$legacy")" = "$ssz" ]; then
    echo "rename: $rel -> $dest"
    if [ "$DRY" -eq 0 ]; then mkdir -p "$(dirname "$d")"; mv -- "$legacy" "$d"; fi
    renamed=$((renamed+1)); continue
  fi
  echo "copy:   $dest"
  if [ "$DRY" -eq 0 ]; then mkdir -p "$(dirname "$d")"; rsync -t --partial "$s" "$d"; fi
  copied=$((copied+1))
done < "$WORK/map"

# Remove card files (within Movies/ and TV/) that the manifest no longer lists.
cut -f1 "$WORK/map" | sort > "$WORK/want"
for top in Movies TV; do
  [ -d "$MOUNT/$top" ] && (cd "$MOUNT" && find "$top" -type f)
done | sort | comm -23 - "$WORK/want" > "$WORK/stale"
if [ -s "$WORK/stale" ]; then
  echo "Removing $(wc -l < "$WORK/stale") stale file(s):"
  sed 's/^/  - /' "$WORK/stale"
  if [ "$DRY" -eq 0 ]; then
    while IFS= read -r f; do rm -f -- "$MOUNT/$f"; done < "$WORK/stale"
    find "$MOUNT" -mindepth 1 -type d -empty -delete
  fi
fi

echo "copied $copied, renamed $renamed, $(wc -l < "$WORK/stale") removed"
if [ "$DRY" -eq 0 ]; then
  cut -f1 "$WORK/map" > "$MOUNT/$MANIFEST"
  sync
fi
df -h "$MOUNT" | tail -1 | awk '{print "Card usage: "$3" used, "$4" free ("$5")"}'
echo "Done."
