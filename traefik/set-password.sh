#!/usr/bin/env bash
# Set/replace a basic-auth user for the Structurizr Server route (ADR 0015).
# Prompts silently (nothing echoes, nothing lands in argv/history/logs), hashes
# with APR1, and rewrites that user's line in the gitignored usersfile.
# Traefik loads the usersfile only when the middleware is (re)created, NOT per
# request — so this script restarts Traefik (a few seconds' blip on all routes).
# Usage: traefik/set-password.sh [username]   (default: dave)
set -euo pipefail
cd "$(dirname "$0")"

user=${1:-dave}
file=users/structurizr.htpasswd

read -r -s -p "new password for '$user': " pw1; echo
read -r -s -p "confirm: " pw2; echo
[ "$pw1" = "$pw2" ] || { echo "passwords do not match" >&2; exit 1; }
[ -n "$pw1" ] || { echo "empty password refused" >&2; exit 1; }

hash=$(openssl passwd -apr1 "$pw1")
mkdir -p users
touch "$file"
grep -v "^$user:" "$file" > "$file.tmp" || true
printf '%s:%s\n' "$user" "$hash" >> "$file.tmp"
mv "$file.tmp" "$file"
chmod 600 "$file"
echo "updated $user in $file"
echo "restarting traefik to load the new credential..."
docker restart traefik >/dev/null
echo "done — log in as '$user' now"
