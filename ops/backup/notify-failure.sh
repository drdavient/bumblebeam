#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE=${BACKUP_ENV_FILE:-$SCRIPT_DIR/backup.env}
[[ -r "$ENV_FILE" ]] && source "$ENV_FILE"

unit=${1:-unknown-unit}
message="Bumblebeam backup unit failed: $unit"
logger --tag bumblebeam-backup -- "$message" 2>/dev/null || true
printf 'ERROR: %s\n' "$message" >&2

if [[ -n "${ALERT_URL:-}" ]] && command -v curl >/dev/null && command -v jq >/dev/null; then
  curl --fail --silent --show-error --max-time 15 \
    --header 'Content-Type: application/json' \
    --data "$(jq -nc --arg text "$message" '{text:$text}')" \
    "$ALERT_URL" >/dev/null
fi
