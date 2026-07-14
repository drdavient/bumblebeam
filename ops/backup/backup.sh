#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
export PATH="${RESTIC_BIN_DIR:-$ROOT_DIR/.local/usr/bin}:$PATH"
ENV_FILE=${BACKUP_ENV_FILE:-$SCRIPT_DIR/backup.env}

if [[ ! -r "$ENV_FILE" ]]; then
  printf 'ERROR: backup configuration is missing: %s\n' "$ENV_FILE" >&2
  exit 2
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${ELEMENTS_MOUNT:?}"
: "${ELEMENTS_UUID:?}"
: "${LOCAL_REPOSITORY:?}"
: "${LOCAL_PASSWORD_FILE:?}"

CONSISTENT=0
CHECK_AFTER=0
COPY_REMOTE=0
while (($#)); do
  case "$1" in
    --consistent) CONSISTENT=1 ;;
    --check) CHECK_AFTER=1 ;;
    --copy-remote) COPY_REMOTE=1 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

log() { printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"; }

alert() {
  local message=$1
  log "ERROR: $message" >&2
  if [[ -n "${ALERT_URL:-}" ]] && command -v curl >/dev/null; then
    curl --fail --silent --show-error --max-time 15 \
      --header 'Content-Type: application/json' \
      --data "$(jq -nc --arg text "$message" '{text:$text}')" \
      "$ALERT_URL" >/dev/null || true
  fi
}

on_error() {
  local status=$?
  alert "Bumblebeam backup failed at line ${BASH_LINENO[0]} (exit $status)"
  exit "$status"
}
trap on_error ERR

command -v findmnt >/dev/null || { alert 'findmnt is not installed'; exit 2; }

mount_record=$(findmnt -rn -T "$ELEMENTS_MOUNT" -o UUID,OPTIONS 2>/dev/null \
  | awk -v expected_uuid="$ELEMENTS_UUID" '$1 == expected_uuid { print; exit }' || true)
read -r mount_uuid mount_options <<<"$mount_record"
if [[ "$mount_uuid" != "$ELEMENTS_UUID" ]]; then
  alert "Elements UUID mismatch or disk absent (expected $ELEMENTS_UUID, got ${mount_uuid:-none})"
  exit 3
fi
if ! tr ',' '\n' <<<"$mount_options" | grep -qx rw; then
  alert 'Elements is not mounted read-write; refusing backup'
  exit 3
fi
if [[ ! -f "$ELEMENTS_MOUNT/.mount-ok" ]]; then
  alert 'Elements sentinel .mount-ok is missing; refusing backup'
  exit 3
fi
case "$(realpath -m -- "$LOCAL_REPOSITORY")" in
  "$(realpath -m -- "$ELEMENTS_MOUNT")"/*) ;;
  *) alert 'LOCAL_REPOSITORY is outside Elements; refusing unsafe fallback'; exit 3 ;;
esac

command -v restic >/dev/null || { alert 'restic is not installed'; exit 2; }

for password_file in "$LOCAL_PASSWORD_FILE"; do
  [[ -r "$password_file" ]] || { alert "password file is unreadable: $password_file"; exit 4; }
  mode=$(stat -c '%a' "$password_file")
  [[ "$mode" == 600 || "$mode" == 400 ]] || {
    alert "password file must have mode 600 or 400: $password_file"; exit 4;
  }
done

exec 9>"${BACKUP_LOCK_FILE:-/tmp/bumblebeam-restic.lock}"
flock -n 9 || { alert 'another Bumblebeam backup is already running'; exit 5; }

mkdir -p -- "$LOCAL_REPOSITORY"
if [[ ! -f "$LOCAL_REPOSITORY/config" ]]; then
  log "initialising local Restic repository"
  restic -r "$LOCAL_REPOSITORY" --password-file "$LOCAL_PASSWORD_FILE" init
fi

running_containers=()
stateful_containers=(deluge radarr sonarr prowlarr jackett n8n homeassistant plex traefik)
restart_containers() {
  if ((${#running_containers[@]})); then
    log "restarting previously running containers: ${running_containers[*]}"
    docker start "${running_containers[@]}" >/dev/null
    running_containers=()
  fi
}
trap restart_containers EXIT

if ((CONSISTENT)); then
  command -v docker >/dev/null || { alert 'docker is required for a consistent snapshot'; exit 6; }
  docker info >/dev/null
  for container in "${stateful_containers[@]}"; do
    if [[ $(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true) == true ]]; then
      running_containers+=("$container")
    fi
  done
  if ((${#running_containers[@]})); then
    log "stopping stateful containers: ${running_containers[*]}"
    docker stop --time 60 "${running_containers[@]}" >/dev/null
  fi
fi

paths=(
  "$ROOT_DIR/.agents"
  "$ROOT_DIR/.claude"
  "$ROOT_DIR/.gitignore"
  "$ROOT_DIR/AGENTS.md"
  "$ROOT_DIR/CLAUDE.md"
  "$ROOT_DIR/README.md"
  "$ROOT_DIR/docs"
  "$ROOT_DIR/ops"
  "$ROOT_DIR/HomeAssistant"
  "$ROOT_DIR/n8n"
  "$ROOT_DIR/Home_Media"
  "$ROOT_DIR/traefik"
  "$ROOT_DIR/portal"
  "$ROOT_DIR/cloudflare-ddns"
  "$ROOT_DIR/mount-watcher"
  "$ROOT_DIR/pla-util"
  "$ROOT_DIR/structurizr-lite"
  "$ROOT_DIR/plex/compose.yml"
  "$ROOT_DIR/plex/split_multi.sh"
  "$ROOT_DIR/plex/mergeParts.sh"
)

# Plex's compose environment contains the runtime token and is intentionally
# ignored by Git, but it is required for a complete encrypted recovery.
[[ -e "$ROOT_DIR/plex/.env" ]] && paths+=("$ROOT_DIR/plex/.env")

plex_root="$ROOT_DIR/plex/PMS/Library/Application Support/Plex Media Server"
for plex_path in \
  "$plex_root/Preferences.xml" \
  "$plex_root/Plug-in Support/Databases" \
  "$plex_root/Plug-in Support/Preferences"; do
  [[ -e "$plex_path" ]] && paths+=("$plex_path")
done

log 'creating encrypted local snapshot'
restic -r "$LOCAL_REPOSITORY" --password-file "$LOCAL_PASSWORD_FILE" backup \
  --exclude-file "$SCRIPT_DIR/excludes.txt" \
  --tag bumblebeam --tag "$(hostname -s)" \
  "${paths[@]}"

restart_containers
trap - EXIT

if ((CHECK_AFTER)); then
  log 'checking local repository structure and data'
  restic -r "$LOCAL_REPOSITORY" --password-file "$LOCAL_PASSWORD_FILE" check --read-data
fi

if ((COPY_REMOTE)); then
  : "${REMOTE_REPOSITORY:?REMOTE_REPOSITORY is required for --copy-remote}"
  : "${REMOTE_PASSWORD_FILE:?REMOTE_PASSWORD_FILE is required for --copy-remote}"
  [[ -r "$REMOTE_PASSWORD_FILE" ]] || { alert 'remote password file is unreadable'; exit 4; }
  remote_mode=$(stat -c '%a' "$REMOTE_PASSWORD_FILE")
  [[ "$remote_mode" == 600 || "$remote_mode" == 400 ]] || {
    alert 'remote password file must have mode 600 or 400'; exit 4;
  }
  if ! restic -r "$REMOTE_REPOSITORY" --password-file "$REMOTE_PASSWORD_FILE" snapshots >/dev/null 2>&1; then
    log 'initialising remote Restic repository'
    restic -r "$REMOTE_REPOSITORY" --password-file "$REMOTE_PASSWORD_FILE" init
  fi
  log 'copying snapshots with Restic repository awareness'
  restic -r "$REMOTE_REPOSITORY" --password-file "$REMOTE_PASSWORD_FILE" copy \
    --from-repo "$LOCAL_REPOSITORY" --from-password-file "$LOCAL_PASSWORD_FILE"
fi

log 'backup completed successfully'
