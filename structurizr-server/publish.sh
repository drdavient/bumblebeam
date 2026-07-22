#!/usr/bin/env bash
# Publish a DSL file to a Structurizr Server workspace (open core, file storage).
# Open core has no admin/workspace API for pushes, so publishing renders the
# versioned DSL to workspace JSON and places it in the workspace's data
# directory; the server (structurizr.cache=none) serves it immediately.
# Usage: publish.sh <workspace-id> <path-to-workspace.dsl>
set -euo pipefail

id=$1
dsl=$(realpath "$2")
cd "$(dirname "$0")"
[ -d "data/$id" ] || { echo "workspace data/$id does not exist (create it in the UI: /workspace/create)" >&2; exit 1; }
image=$(sed -n 's/.*image:[[:space:]]*//p' compose.yml)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
docker run --rm -u 1000:1000 \
  -v "$(dirname "$dsl")":/w:ro -v "$tmp":/out \
  "$image" export -w "/w/$(basename "$dsl")" -f json -o /out
mv "$tmp"/*.json "data/$id/workspace.json"
echo "published $(basename "$dsl") -> workspace $id"
