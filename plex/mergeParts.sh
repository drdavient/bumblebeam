#!/usr/bin/env bash
set -euo pipefail

DIR="/mnt/Elements/Video/TV/One Piece"

cd "$DIR" || { echo "Cannot cd to $DIR" >&2; exit 1; }

# Check ffmpeg exists
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found. Install it with: sudo apt install ffmpeg" >&2
  exit 1
fi

echo "Merging multi part One Piece episodes in: $DIR"
echo

shopt -s nullglob

# Loop over any part 1 files in any supported container
for part1 in *"Part 1".mp4 *"Part 1".mkv *"Part 1".avi *"Part 1".flv; do
  [ -f "$part1" ] || continue

  # Extract episode number at the start of the file name
  # Example: '561. A Battle ... - Part 1.mp4' -> 561
  ep_num=$(echo "$part1" | sed -E 's/^([0-9]+).*/\1/')
  ext="${part1##*.}"

  out_file="One Piece - ${ep_num}.${ext}"

  # Find all parts for this episode with the same extension
  # Example pattern: '561. *Part *.mp4'
  mapfile -t parts < <(printf '%s\n' "${ep_num}."*"Part "*".${ext}" | sort)

  if [ "${#parts[@]}" -lt 2 ]; then
    echo "Episode ${ep_num}: only one part found, skipping"
    continue
  fi

  if [ -f "$out_file" ]; then
    echo "Episode ${ep_num}: output ${out_file} already exists, skipping"
    continue
  fi

  echo "Episode ${ep_num}: merging ${#parts[@]} parts into ${out_file}"

tmp_list=$(mktemp)
trap 'rm -f "$tmp_list"' EXIT

for p in "${parts[@]}"; do
    fullpath="$DIR/$p"
    # Escape single quotes for ffmpeg concat syntax
    escaped=$(printf "%s" "$fullpath" | sed "s/'/'\\\\''/g")
    printf "file '%s'\n" "$escaped" >> "$tmp_list"
done

if ffmpeg -hide_banner -loglevel error -f concat -safe 0 -i "$tmp_list" -c copy "$out_file"; then
    echo "Episode ${ep_num}: merge ok, removing part files"
    rm -- "${parts[@]}"
else
    echo "Episode ${ep_num}: merge FAILED, leaving part files in place" >&2
    rm -f "$out_file"
fi

rm -f "$tmp_list"
trap - EXIT

done

echo
echo "Done. Now run a Sonarr rescan and rename pass for One Piece."
