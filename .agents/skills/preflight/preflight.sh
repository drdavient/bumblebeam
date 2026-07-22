#!/usr/bin/env bash
# preflight.sh — read-only session-start anomaly report for this repo.
#
# Single implementation: the /preflight skill and the claude-code SessionStart
# hook both delegate to this file — never restate its logic elsewhere.
# It reports; it never fixes anything; it always exits 0 (a broken preflight
# must not block a session).
set -uo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 0
cd "$script_dir/../../.." || exit 0   # repo root; script lives in .agents/skills/preflight/

run_source=manual                     # hook/cron invocations pass --source=hook / --source=cron
case "${1:-}" in --source=*) run_source="${1#--source=}" ;; esac

findings=()
keys=()
add() { keys+=("$1"); shift; findings+=("$*"); }

# --- git state ---------------------------------------------------------------
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
if upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then
  counts=$(git rev-list --left-right --count "$upstream"...HEAD 2>/dev/null || echo "0	0")
  behind=${counts%%	*}; ahead=${counts##*	}
  [ "$ahead" != 0 ] && add unpushed "$ahead commit(s) on $branch not pushed to $upstream"
  [ "$behind" != 0 ] && add behind "$branch is $behind commit(s) behind $upstream (fetch age unknown — consider git fetch)"
else
  add no-upstream "branch $branch has no upstream configured"
fi

status=$(git status --porcelain 2>/dev/null || true)
n_mod=$(printf '%s' "$status" | grep -c '^[^?]' || true)
n_untracked=$(printf '%s' "$status" | grep -c '^??' || true)
[ "$n_mod" != 0 ] || [ "$n_untracked" != 0 ] && \
  add dirty-tree "working tree: $n_mod modified/staged, $n_untracked untracked path(s) (normal mid-work; commit per workstream when done)"

# --- untracked compose stacks ------------------------------------------------
while IFS= read -r d; do
  d=${d%/}
  [ -z "$d" ] && continue
  if [ -f "$d/compose.yml" ] || [ -f "$d/docker-compose.yml" ]; then
    add unregistered-stack "unregistered stack: untracked directory $d/ contains a compose file"
  fi
done < <(git ls-files --others --exclude-standard --directory 2>/dev/null | grep '^[^/]*/$' || true)

# --- running containers vs tracked compose files -----------------------------
if running=$(timeout 5 docker ps --format '{{.Names}}' 2>/dev/null); then
  tracked=$(git ls-files '*compose*.yml' '*compose*.yaml' 2>/dev/null \
            | xargs -r grep -h 'container_name' 2>/dev/null \
            | sed 's/.*container_name:[[:space:]]*//; s/["'\'']//g; s/[[:space:]]*$//' \
            | sort -u)
  unknown=""
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    grep -qxF "$c" <<<"$tracked" || unknown="$unknown $c"
  done <<<"$running"
  [ -n "$unknown" ] && add unknown-containers "running container(s) named in no tracked compose file:$unknown"
else
  add docker-unavailable "docker ps unavailable (daemon down or >5s timeout) — container check skipped"
fi

# --- versioned git hooks wired? ----------------------------------------------
hooks_path=$(git config core.hooksPath 2>/dev/null || true)
if [ "$hooks_path" != "ops/git-hooks" ]; then
  add hooks-unwired "git hooks unwired for this clone — run: git config core.hooksPath ops/git-hooks"
fi

# --- run log (gitignored via *.log; the monitoring evidence — ADR 0012) ------
printf '%s source=%s branch=%s findings=%s keys=%s\n' \
  "$(date -Is)" "$run_source" "$branch" "${#findings[@]}" \
  "$(IFS=,; echo "${keys[*]:-none}")" >> "$script_dir/runs.log" 2>/dev/null || true

# --- report ------------------------------------------------------------------
if [ ${#findings[@]} -eq 0 ]; then
  echo "PREFLIGHT OK — branch $branch: clean tree, hooks wired, no unregistered stacks or unknown containers"
else
  echo "PREFLIGHT — ${#findings[@]} finding(s) for branch $branch:"
  for f in "${findings[@]}"; do echo "  - $f"; done
fi
exit 0
