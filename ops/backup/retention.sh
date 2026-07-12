#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
export PATH="${RESTIC_BIN_DIR:-$ROOT_DIR/.local/usr/bin}:$PATH"
# shellcheck disable=SC1090
source "${BACKUP_ENV_FILE:-$SCRIPT_DIR/backup.env}"

repo=${1:-local}
mode=${2:---dry-run}
case "$repo" in
  local) repository=$LOCAL_REPOSITORY; password_file=$LOCAL_PASSWORD_FILE ;;
  remote) repository=$REMOTE_REPOSITORY; password_file=$REMOTE_PASSWORD_FILE ;;
  *) printf 'Usage: %s [local|remote] [--dry-run|--apply]\n' "$0" >&2; exit 2 ;;
esac
case "$mode" in
  --dry-run) extra=(--dry-run) ;;
  --apply) extra=(--prune) ;;
  *) printf 'Second argument must be --dry-run or --apply\n' >&2; exit 2 ;;
esac

restic -r "$repository" --password-file "$password_file" forget \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 12 "${extra[@]}"
