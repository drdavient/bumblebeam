#!/usr/bin/env bash
# Verify a basic-auth credential against the live structurizr route, keeping
# the password out of argv, history, and logs (silent prompt; curl reads the
# credential from an anonymous config fd, never the command line).
# 200 = credential is good (any browser failure is browser-side caching).
# 401 = stored hash does not match what you typed -> re-run set-password.sh.
# Usage: traefik/check-password.sh [username]   (default: dave)
set -euo pipefail
user=${1:-dave}
read -r -s -p "password for '$user': " pw; echo
code=$(curl -s -o /dev/null -w '%{http_code}' \
  -K <(printf 'user = "%s:%s"\n' "$user" "$pw") \
  -H 'Host: structurizr.svc.home.arpa' http://localhost/)
unset pw
case "$code" in
  200) echo "OK ($code) — the credential works; a browser failure means cached/autofilled credentials there" ;;
  401) echo "REJECTED ($code) — stored hash does not match what you typed; re-run: traefik/set-password.sh $user (type it by hand rather than pasting)" ;;
  *)   echo "unexpected HTTP $code — is the structurizr-server stack up?" ;;
esac
