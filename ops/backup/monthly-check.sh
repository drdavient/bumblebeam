#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
export PATH="${RESTIC_BIN_DIR:-$ROOT_DIR/.local/usr/bin}:$PATH"
# shellcheck disable=SC1090
source "${BACKUP_ENV_FILE:-$SCRIPT_DIR/backup.env}"

subset_part=$((10#$(date +%m)))
restic -r "$LOCAL_REPOSITORY" --password-file "$LOCAL_PASSWORD_FILE" check \
  --read-data-subset "${subset_part}/12"
"$SCRIPT_DIR/restore-test.sh" local

if [[ -n "${REMOTE_REPOSITORY:-}" ]]; then
  restic -r "$REMOTE_REPOSITORY" --password-file "$REMOTE_PASSWORD_FILE" check
  "$SCRIPT_DIR/restore-test.sh" remote
fi
