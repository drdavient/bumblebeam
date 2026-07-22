#!/usr/bin/env bash
# Publish a DSL file to a Structurizr Server workspace (open core, file storage).
# Open core has no admin/workspace API for pushes, so publishing renders the
# versioned DSL to workspace JSON and places it in the workspace's data
# directory; the server (structurizr.cache=none) serves it immediately.
# Thumbnails are rendered automatically (light + dark) with the playwright
# renderer image — no manual editor saves needed.
# Mounts the repo root read-only so DSL directives may reference repo paths
# (e.g. !decisions ../../docs/adr).
# Usage: publish.sh <workspace-id> <path-to-workspace.dsl>
set -euo pipefail

id=$1
dsl=$(realpath "$2")
root=$(git -C "$(dirname "$dsl")" rev-parse --show-toplevel)
rel=${dsl#"$root"/}
cd "$(dirname "$0")"
[ -d "data/$id" ] || { echo "workspace data/$id does not exist (create it in the UI: /workspace/create)" >&2; exit 1; }

image=$(sed -n 's/.*image:[[:space:]]*//p' compose.yml | head -1)
renderer="${image/structurizr-server/structurizr-renderer}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/json" "$tmp/light" "$tmp/dark"
mkdir -p "data/.structurizr/$id/images"

docker run --rm -u 1000:1000 -v "$root":/repo:ro -v "$tmp/json":/out \
  "$image" export -w "/repo/$rel" -f json -o /out
mv "$tmp/json"/*.json "data/$id/workspace.json"

for mode in light dark; do
  docker run --rm -u 1000:1000 --ipc=host -v "$root":/repo:ro -v "$tmp/$mode":/out \
    "$renderer" export -w "/repo/$rel" -f png -mode "$mode" -o /out
done
suffix() { [ "$1" = dark ] && echo '-thumbnail-dark.png' || echo '-thumbnail.png'; }
for mode in light dark; do
  for png in "$tmp/$mode"/*.png; do
    base=$(basename "$png" .png)
    case "$base" in *-key) continue ;; esac
    cp "$png" "data/.structurizr/$id/images/${base}$(suffix "$mode")"
  done
  # workspace-level dashboard thumbnail: first diagram (SystemContext if present)
  first=$(ls "$tmp/$mode"/*.png | grep -v -- '-key.png' | { grep -i systemcontext || true; } | head -1)
  [ -n "$first" ] || first=$(ls "$tmp/$mode"/*.png | grep -v -- '-key.png' | head -1)
  [ "$mode" = dark ] && cp "$first" "data/.structurizr/$id/images/thumbnail-dark.png" || cp "$first" "data/.structurizr/$id/images/thumbnail.png"
done

echo "published $rel -> workspace $id ($(ls "$tmp/light"/*.png 2>/dev/null | grep -vc -- '-key.png') diagrams + thumbnails)"
