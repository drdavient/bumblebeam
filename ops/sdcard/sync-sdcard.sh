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
# — and each file gets the item's 16:9 Plex background art EMBEDDED (mp4/mov:
# attached_pic; mkv: cover.jpg attachment) so VLC's library tiles show real
# artwork instead of frame grabs. Episodes carry their show's backdrop. The
# copy-check tolerates the small size the art adds, so embedded files are not
# endlessly recopied. Episodes Plex couldn't parse fall back to their original
# basename inside the show folder; formats that can't embed art (avi) are
# synced without it.
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
ART_SLACK=2097152   # embedded art head-room the copy-check tolerates (bytes)

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
plex_img() {  # <plex art path> <out.jpg> — fetch 16:9-fitted artwork
  local enc
  enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1")
  curl -sf --max-time 30 -K <(printf 'header = "X-Plex-Token: %s"\n' "$TOKEN") \
    -o "$2" "$PLEX/photo/:/transcode?width=800&height=450&minSize=1&url=$enc"
}

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/art"
: > "$WORK/map"   # lines: dest<TAB>source-rel-path<TAB>plex-art-path
declare -A SEEN

emit() { # <dest> <container-file-path> <art-path>
  local dest="$1" f="$2" art="${3:-}" rel
  rel="${f#/media/}"
  if [ "$rel" = "$f" ]; then echo "WARN: non-/media path skipped: $f" >&2; return; fi
  if [ ! -f "$SRC/$rel" ]; then echo "WARN: missing on host, skipped: $rel" >&2; return; fi
  if [ -n "${SEEN[$dest]:-}" ]; then dest="${dest%/*}/$(basename "$rel")"; fi
  if [ -n "${SEEN[$dest]:-}" ]; then echo "WARN: duplicate dest skipped: $dest" >&2; return; fi
  SEEN[$dest]=1
  printf '%s\t%s\t%s\n' "$dest" "$rel" "$art" >> "$WORK/map"
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
          mjson=$(plex "/library/metadata/$rk")
          art=$(jq -r '.MediaContainer.Metadata[0] | .art // .thumb // ""' <<<"$mjson")
          local_title=$(san "$title"); [ -n "$year" ] && local_title="$local_title ($year)"
          n=0
          while IFS= read -r f; do
            [ -n "$f" ] || continue
            n=$((n+1)); ext="${f##*.}"
            suffix=""; [ "$n" -gt 1 ] && suffix=" - pt$n"
            emit "Movies/$local_title$suffix.$ext" "$f" "$art"
          done < <(jq -r '.MediaContainer.Metadata[].Media[]?.Part[]?.file // empty' <<<"$mjson")
          ;;
        show|season)
          show=$(san "${ptitle:-$title}"); [ "$type" = "show" ] && show=$(san "$title")
          art=$(plex "/library/metadata/$rk" | jq -r '.MediaContainer.Metadata[0] | .art // .grandparentArt // .thumb // ""')
          leaves="/library/metadata/$rk/allLeaves"; [ "$type" = "season" ] && leaves="/library/metadata/$rk/children"
          while IFS=$'\t' read -r snum enum etitle f; do
            [ -n "$f" ] || continue
            ext="${f##*.}"
            if [ "${enum:-0}" -gt 0 ] 2>/dev/null; then
              ep=$(printf 'S%02dE%02d' "$snum" "$enum")
              name="$show - $ep"; [ -n "$etitle" ] && name="$name - $(san "$etitle")"
              emit "TV/$show/Season $(printf '%02d' "$snum")/$name.$ext" "$f" "$art"
            else
              emit "TV/$show/$(basename "$f")" "$f" "$art"
            fi
          done < <(plex "$leaves" \
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

get_art_jpg() { # <plex art path> -> cached jpg path on stdout ('' on failure)
  local jpg="$WORK/art/$(printf '%s' "$1" | md5sum | cut -d' ' -f1).jpg"
  [ -s "$jpg" ] || plex_img "$1" "$jpg" || { rm -f "$jpg"; echo ""; return 0; }
  echo "$jpg"
}

embeddable() { case "${1,,}" in mp4|m4v|mov|mkv) return 0 ;; *) return 1 ;; esac; }

copied=0 renamed=0
while IFS=$'\t' read -r dest rel art; do
  s="$SRC/$rel"; d="$MOUNT/$dest"
  ssz=$(stat -c%s "$s")
  if [ -f "$d" ]; then
    dsz=$(stat -c%s "$d")
    diff=$((dsz - ssz)); [ "$diff" -lt 0 ] && diff=$((-diff))
    [ "$diff" -lt "$ART_SLACK" ] && continue
  fi
  legacy="$MOUNT/$rel"
  if [ "$legacy" != "$d" ] && [ -f "$legacy" ] && [ "$(stat -c%s "$legacy")" = "$ssz" ]; then
    echo "rename: $rel -> $dest"
    if [ "$DRY" -eq 0 ]; then mkdir -p "$(dirname "$d")"; mv -- "$legacy" "$d"; fi
    renamed=$((renamed+1)); continue
  fi
  # Copy — embedding the art during the copy itself when possible, so new
  # files never need a second rewrite on the card.
  ext="${dest##*.}"; jpg=""
  [ -n "$art" ] && embeddable "$ext" && jpg=$(get_art_jpg "$art")
  if [ -n "$jpg" ]; then
    echo "copy+art: $dest"
    if [ "$DRY" -eq 0 ]; then
      mkdir -p "$(dirname "$d")"; tmp="$(dirname "$d")/.copy-tmp.${ext,,}"
      ok=0
      case "${ext,,}" in
        mkv) ffmpeg -y -nostdin -v error -i "$s" -c copy -map 0 \
               -attach "$jpg" -metadata:s:t mimetype=image/jpeg -metadata:s:t filename=cover.jpg "$tmp" && ok=1 || true ;;
        *)   ffmpeg -y -nostdin -v error -i "$s" -i "$jpg" -map 0 -map 1:0 -c copy \
               -disposition:v:1 attached_pic "$tmp" && ok=1 || true ;;
      esac
      if [ "$ok" -eq 1 ] && [ -s "$tmp" ]; then mv -- "$tmp" "$d"; else
        rm -f -- "$tmp"; echo "WARN: embed-copy failed, plain copy: $dest" >&2
        rsync -t --partial "$s" "$d"
      fi
    fi
  else
    echo "copy:   $dest"
    if [ "$DRY" -eq 0 ]; then mkdir -p "$(dirname "$d")"; rsync -t --partial "$s" "$d"; fi
  fi
  copied=$((copied+1))
done < "$WORK/map"

# Art pass: embed 16:9 Plex background art into files that lack artwork.
has_art() {
  ffprobe -v error -show_streams -of json "$1" 2>/dev/null \
    | jq -e '[.streams[] | select((.disposition.attached_pic // 0) == 1 or .codec_type == "attachment")] | length > 0' >/dev/null
}
arted=0
while IFS=$'\t' read -r dest rel art; do
  [ -n "$art" ] || continue
  d="$MOUNT/$dest"; ext="${dest##*.}"
  embeddable "$ext" || continue
  [ -f "$d" ] || continue
  has_art "$d" && continue
  jpg=$(get_art_jpg "$art")
  [ -n "$jpg" ] || { echo "WARN: art fetch failed: $dest" >&2; continue; }
  echo "art:    $dest"
  [ "$DRY" -eq 1 ] && { arted=$((arted+1)); continue; }
  tmp="$(dirname "$d")/.art-tmp.${ext,,}"
  ok=0
  case "${ext,,}" in
    mkv)
      ffmpeg -y -nostdin -v error -i "$d" -c copy -map 0 \
        -attach "$jpg" -metadata:s:t mimetype=image/jpeg -metadata:s:t filename=cover.jpg "$tmp" && ok=1 || true ;;
    *)
      ffmpeg -y -nostdin -v error -i "$d" -i "$jpg" -map 0 -map 1:0 -c copy \
        -disposition:v:1 attached_pic "$tmp" && ok=1 || true ;;
  esac
  if [ "$ok" -eq 1 ] && [ -s "$tmp" ]; then
    mv -- "$tmp" "$d"; arted=$((arted+1))
  else
    rm -f -- "$tmp"; echo "WARN: art embed failed: $dest" >&2
  fi
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

echo "copied $copied, renamed $renamed, art-embedded $arted, $(wc -l < "$WORK/stale") removed"
if [ "$DRY" -eq 0 ]; then
  cut -f1 "$WORK/map" > "$MOUNT/$MANIFEST"
  sync
fi
df -h "$MOUNT" | tail -1 | awk '{print "Card usage: "$3" used, "$4" free ("$5")"}'
echo "Done."
