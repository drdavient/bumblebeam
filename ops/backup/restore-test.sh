#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
export PATH="${RESTIC_BIN_DIR:-$ROOT_DIR/.local/usr/bin}:$PATH"
ENV_FILE=${BACKUP_ENV_FILE:-$SCRIPT_DIR/backup.env}
# shellcheck disable=SC1090
source "$ENV_FILE"

repository=${1:-local}
case "$repository" in
  local) repo=$LOCAL_REPOSITORY; password_file=$LOCAL_PASSWORD_FILE ;;
  remote) repo=$REMOTE_REPOSITORY; password_file=$REMOTE_PASSWORD_FILE ;;
  *) printf 'Usage: %s [local|remote]\n' "$0" >&2; exit 2 ;;
esac

target=$(mktemp -d /tmp/bumblebeam-restore.XXXXXX)
trap 'rm -rf -- "$target"' EXIT

restic -r "$repo" --password-file "$password_file" restore latest \
  --target "$target" \
  --include "$ROOT_DIR/HomeAssistant/compose.yml" \
  --include "$ROOT_DIR/HomeAssistant/hadata/secrets.yaml" \
  --include "$ROOT_DIR/HomeAssistant/hadata/home-assistant_v2.db" \
  --include "$ROOT_DIR/n8n/data/database.sqlite" \
  --include "$ROOT_DIR/portal/site/index.html" \
  --include "$ROOT_DIR/.agents/AGENTS.md" \
  --include "$ROOT_DIR/mount-watcher/mount-rebooter.sh" \
  --include "$ROOT_DIR/plex/PMS/Library/Application Support/Plex Media Server/Preferences.xml" \
  --include "$ROOT_DIR/plex/PMS/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db" \
  --include "$ROOT_DIR/traefik/traefik.yml"

restored_root="$target${ROOT_DIR}"
required=(
  "$restored_root/HomeAssistant/compose.yml"
  "$restored_root/HomeAssistant/hadata/secrets.yaml"
  "$restored_root/HomeAssistant/hadata/home-assistant_v2.db"
  "$restored_root/n8n/data/database.sqlite"
  "$restored_root/portal/site/index.html"
  "$restored_root/.agents/AGENTS.md"
  "$restored_root/mount-watcher/mount-rebooter.sh"
  "$restored_root/plex/PMS/Library/Application Support/Plex Media Server/Preferences.xml"
  "$restored_root/plex/PMS/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
  "$restored_root/traefik/traefik.yml"
)
for file in "${required[@]}"; do
  [[ -s "$file" ]] || { printf 'Restore verification failed: %s\n' "$file" >&2; exit 1; }
done
printf 'Restore verification passed from %s repository.\n' "$repository"
