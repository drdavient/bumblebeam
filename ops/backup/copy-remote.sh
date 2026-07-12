#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
export PATH="${RESTIC_BIN_DIR:-$ROOT_DIR/.local/usr/bin}:$PATH"
# shellcheck disable=SC1090
source "${BACKUP_ENV_FILE:-$SCRIPT_DIR/backup.env}"

: "${LOCAL_REPOSITORY:?}"
: "${LOCAL_PASSWORD_FILE:?}"
: "${REMOTE_REPOSITORY:?}"
: "${REMOTE_PASSWORD_FILE:?}"

for file in "$LOCAL_PASSWORD_FILE" "$REMOTE_PASSWORD_FILE"; do
  [[ -r "$file" ]] || { printf 'Password file is unreadable: %s\n' "$file" >&2; exit 2; }
  mode=$(stat -c '%a' "$file")
  [[ "$mode" == 600 || "$mode" == 400 ]] || {
    printf 'Password file must have mode 600 or 400: %s\n' "$file" >&2; exit 2;
  }
done

restic -r "$LOCAL_REPOSITORY" --password-file "$LOCAL_PASSWORD_FILE" snapshots --latest 1 >/dev/null
if ! restic -r "$REMOTE_REPOSITORY" --password-file "$REMOTE_PASSWORD_FILE" snapshots >/dev/null 2>&1; then
  printf 'Initialising remote Restic repository\n'
  restic -r "$REMOTE_REPOSITORY" --password-file "$REMOTE_PASSWORD_FILE" init
fi

printf 'Copying verified local snapshots to remote with Restic\n'
restic -r "$REMOTE_REPOSITORY" --password-file "$REMOTE_PASSWORD_FILE" copy \
  --from-repo "$LOCAL_REPOSITORY" --from-password-file "$LOCAL_PASSWORD_FILE"
