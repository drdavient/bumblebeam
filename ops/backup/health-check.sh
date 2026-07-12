#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
export PATH="${RESTIC_BIN_DIR:-$ROOT_DIR/.local/usr/bin}:$PATH"
# shellcheck disable=SC1090
source "${BACKUP_ENV_FILE:-$SCRIPT_DIR/backup.env}"

fail=0
warn() { printf 'ERROR: %s\n' "$*" >&2; fail=1; }

used=$(df --output=pcent "$ELEMENTS_MOUNT" | tail -1 | tr -dc '0-9')
((used < ${LOCAL_USAGE_WARN_PERCENT:-85})) || warn "Elements usage is ${used}%"

latest=$(restic -r "$LOCAL_REPOSITORY" --password-file "$LOCAL_PASSWORD_FILE" \
  snapshots --latest 1 --json | jq -r '.[0].time // empty')
[[ -n "$latest" ]] || warn 'no local snapshot found'
if [[ -n "$latest" ]]; then
  latest_epoch=$(date -d "$latest" +%s)
  age_hours=$(( ($(date +%s) - latest_epoch) / 3600 ))
  ((age_hours <= ${MAX_SNAPSHOT_AGE_HOURS:-36})) || warn "latest snapshot is ${age_hours} hours old"
fi

if [[ -n "${REMOTE_REPOSITORY:-}" ]]; then
  restic -r "$REMOTE_REPOSITORY" --password-file "$REMOTE_PASSWORD_FILE" snapshots --latest 1 >/dev/null \
    || warn 'remote repository unavailable or rclone authorization expired'
fi

exit "$fail"
