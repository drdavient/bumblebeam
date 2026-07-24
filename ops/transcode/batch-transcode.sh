#!/usr/bin/env bash
# batch-transcode.sh <queue-file> — normalise library files to <=1080p H.264/AC3 mkv.
#
# The library-wide playback target is 1080p H.264 (ADR-less convention, 2026-07:
# heaviest client is a Google TV on 2.4GHz WiFi; everything must direct-play).
# For each source path in the queue file (one absolute path per line):
#   - video: re-encode x264 (crf 19 when downscaling 4K, crf 20 at native size),
#     tone-mapping HDR10/HLG to SDR bt709 so colours survive the 8-bit conversion
#   - audio: English tracks (or first track if untagged); aac/ac3/eac3/mp3 are
#     copied, anything else (DTS, TrueHD, opus, ...) becomes AC3
#   - subtitles: English kept, mov_text converted to srt, image subs copied
#   - original is deleted only after the output's duration matches (±5s),
#     then the containing folder is rescanned in Plex
# Resumable: sources already gone are skipped; partial outputs are redone.
set -uo pipefail

QUEUE="${1:?usage: batch-transcode.sh <queue-file>}"
LOG="${LOG:-$(dirname "$QUEUE")/batch-transcode.log}"
PREFS="/home/drdavient/docker/plex/PMS/Library/Application Support/Plex Media Server/Preferences.xml"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

plex_refresh() { # host folder -> rescan in every video section (extra paths are ignored)
  local cpath tok
  cpath=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "${1/\/mnt\/Elements\/Video//media}")
  tok=$(sed -n 's/.*PlexOnlineToken="\([^"]*\)".*/\1/p' "$PREFS")
  for sec in 4 5 6; do
    curl -sf -K <(printf 'header = "X-Plex-Token: %s"\n' "$tok") \
      "http://localhost:32400/library/sections/$sec/refresh?path=$cpath" || true
  done
}

transcode_one() {
  local in="$1"
  [ -f "$in" ] || { log "SKIP (gone): $in"; return 0; }
  local dir stem out
  dir=$(dirname "$in"); stem=$(basename "$in"); stem="${stem%.*}"
  out="$dir/$stem - 1080p.mkv"

  local probe width height transfer crf vf
  probe=$(ffprobe -v error -show_streams -show_format -of json "$in") || { log "FAIL probe: $in"; return 1; }
  width=$(jq -r '[.streams[]|select(.codec_type=="video")][0].width' <<<"$probe")
  height=$(jq -r '[.streams[]|select(.codec_type=="video")][0].height' <<<"$probe")
  transfer=$(jq -r '[.streams[]|select(.codec_type=="video")][0].color_transfer // ""' <<<"$probe")

  # Size calibration (2026-07): library norm is ~2 Mbps / 1.2-1.8G per film
  # (cf. Toy Story 3). CRF alone preserves source grain and can triple that, so
  # every encode gets light temporal denoise plus a 3.5 Mbps ceiling.
  local dn="hqdn3d=1.5:1.5:6:6"; crf=22
  if [ "$transfer" = "smpte2084" ] || [ "$transfer" = "arib-std-b67" ]; then
    if [ "${width:-0}" -gt 1920 ]; then
      vf="zscale=w=1920:h=-2:t=linear:npl=100,tonemap=hable,zscale=p=bt709:t=bt709:m=bt709:r=tv,$dn,format=yuv420p"
    else
      vf="zscale=t=linear:npl=100,tonemap=hable,zscale=p=bt709:t=bt709:m=bt709:r=tv,$dn,format=yuv420p"
    fi
  elif [ "${width:-0}" -gt 1920 ]; then
    vf="scale=1920:-2,$dn,format=yuv420p"
  else
    vf="$dn,format=yuv420p"
  fi

  # audio: English streams, else first; build -map/-c:a args per stream
  local amaps=() acodecs=() n=0 idx codec ch lang have_eng
  have_eng=$(jq -r '[.streams[]|select(.codec_type=="audio")|select((.tags.language // "")=="eng")]|length' <<<"$probe")
  while IFS=$'\t' read -r idx codec ch lang; do
    if [ "$have_eng" -gt 0 ] && [ "$lang" != "eng" ]; then continue; fi
    amaps+=(-map "0:$idx")
    case "$codec" in
      aac|ac3|eac3|mp3) acodecs+=("-c:a:$n" copy) ;;
      *) acodecs+=("-c:a:$n" ac3 "-b:a:$n" 640k); [ "${ch:-2}" -gt 6 ] && acodecs+=("-ac:a:$n" 6) ;;
    esac
    n=$((n+1))
  done < <(jq -r '.streams[]|select(.codec_type=="audio")|[.index,.codec_name,(.channels//2),(.tags.language//"und")]|@tsv' <<<"$probe")
  [ "$n" -gt 0 ] || { amaps=(-map 0:a:0?); acodecs=(-c:a ac3 -b:a 640k); }

  # subtitles: English only; mov_text -> srt, everything else copied
  local smaps=() scodecs=() sn=0
  while IFS=$'\t' read -r idx codec lang; do
    [ "$lang" = "eng" ] || continue
    smaps+=(-map "0:$idx")
    case "$codec" in mov_text) scodecs+=("-c:s:$sn" srt) ;; *) scodecs+=("-c:s:$sn" copy) ;; esac
    sn=$((sn+1))
  done < <(jq -r '.streams[]|select(.codec_type=="subtitle")|[.index,.codec_name,(.tags.language//"und")]|@tsv' <<<"$probe")

  log "START ($(du -h "$in" | cut -f1), ${width}x${height}, tf=${transfer:-sdr}, crf=$crf): $in"
  rm -f -- "$out"
  nice -n 15 ffmpeg -y -nostdin -v error -i "$in" \
    -map 0:v:0 -c:v libx264 -crf "$crf" -preset fast -maxrate 3500k -bufsize 7000k -vf "$vf" \
    "${amaps[@]}" "${acodecs[@]}" \
    ${smaps[0]+"${smaps[@]}"} ${scodecs[0]+"${scodecs[@]}"} \
    "$out" 2>> "$LOG"
  local rc=$?
  [ $rc -eq 0 ] || { log "FAIL encode (rc=$rc): $in"; rm -f -- "$out"; return 1; }

  local din dout
  din=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$in" | cut -d. -f1)
  dout=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out" | cut -d. -f1)
  if [ -z "$dout" ] || [ $((din - dout)) -gt 5 ] || [ $((dout - din)) -gt 5 ]; then
    log "FAIL duration ($din vs ${dout:-none}): $in"; rm -f -- "$out"; return 1
  fi
  rm -- "$in"
  log "DONE ($(du -h "$out" | cut -f1)): $out"
  plex_refresh "$dir"
}

total=$(grep -c . "$QUEUE"); i=0; fails=0
log "=== queue start: $total files ==="
while IFS= read -r f; do
  [ -n "$f" ] || continue
  i=$((i+1)); log "--- [$i/$total] ---"
  transcode_one "$f" || fails=$((fails+1))
done < "$QUEUE"
log "=== queue complete: $((i-fails))/$i ok, $fails failed ==="
[ "$fails" -eq 0 ]
