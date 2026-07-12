#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

DIR="/mnt/Elements/Video/TV/One Piece"
cd "$DIR" || { echo "Cannot cd to directory"; exit 1; }

echo "Auto-splitting multi-episode files in: $DIR"
echo

for f in "One Piece - "*-*.*; do
    # Skip if file name doesn't match the pattern "One Piece - 268-269.ext"
    if [[ "$f" =~ One\ Piece\ \-\ ([0-9]+)\-([0-9]+)\.(.*)$ ]]; then
        ep1="${BASH_REMATCH[1]}"
        ep2="${BASH_REMATCH[2]}"
        ext="${BASH_REMATCH[3]}"

        echo "Found multi-episode file: $f  → episodes $ep1 and $ep2"

        # Check outputs don't already exist
        out1="One Piece - ${ep1}.${ext}"
        out2="One Piece - ${ep2}.${ext}"

        if [[ -e "$out1" || -e "$out2" ]]; then
            echo "Skipping $f because $out1 or $out2 already exists"
            echo
            continue
        fi

        # Get duration in seconds
        duration=$(ffprobe -v error -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1 "$f")

        if [[ -z "$duration" ]]; then
            echo "Could not get duration for $f, skipping"
            echo
            continue
        fi

        # Split point = 50 percent
        midpoint=$(awk -v d="$duration" 'BEGIN { printf "%.3f", d/2 }')

        echo "Duration: $duration seconds"
        echo "Split point: $midpoint seconds"

        echo "Creating: $out1"
        if ! ffmpeg -loglevel error -i "$f" -c copy -map 0 -t "$midpoint" "$out1"; then
            echo "Failed first half for $f"
            rm -f "$out1"
            continue
        fi

        echo "Creating: $out2"
        if ! ffmpeg -loglevel error -i "$f" -c copy -map 0 -ss "$midpoint" "$out2"; then
            echo "Failed second half for $f"
            rm -f "$out1" "$out2"
            continue
        fi

        echo "Split OK → removing original: $f"
        rm "$f"
        echo
    fi
done

echo "Done. Now run a Sonarr rescan and rename."
