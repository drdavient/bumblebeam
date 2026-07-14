# Concurrent agents on Bumblebeam — codify the edit/deploy split (v1)

> **Revision note.** v1 folds in the two-reviewer synthesis
> (`docs/archive/concurrent-agent-workflow/concurrent-agent-workflow-plan-synthesis.md`,
> drawn from the Claude and Codex comment files). Substantive changes from the original draft: the enforcement claim is
> reframed as three labelled layers (socket authority is the only real boundary); the
> "provision the networks" item is **removed** (networks are Compose-owned) and replaced
> by a deploy-ordering rule; two factual errors are corrected (Git remote; lock
> verification no longer live-deploys); the backup gate is stated as operator policy;
> and the framing is safety/isolation, not parallelism.
>
> A subsequent Codex review of v1 is also applied: the blocking `ROOT_DIR` path fix
> (`../..`, not `..`); "host-wide flock" → "repository deploy lock for wrapper callers";
> softened pinned-name wording (may recreate/disrupt, not "fail loudly"); corrected
> lock-test flags (`-n` **or** `-w 1`, not `-n -w1`); network-ordering verification
> restricted to a disposable daemon; plus a precise CLI and test-worktree cleanup.
> A final Codex pass added: broader network-loss phrasing (Docker-state loss / explicit
> removal / prune, not "fresh boot"); consistent "conflict/disrupt/recreate" wording for
> the pinned-name backstop; cleanup that reverts test edits in both trees before
> `git worktree remove`; and parsing `--allow-dirty` before the service arg with a
> realpath **path-boundary** check (not a string prefix). Codex's verdict: ready to
> implement.

## Context

You want to run two AI agents in this repo. The right model is **worktree-per-agent for
isolated editing, but strictly serial deploys from the canonical checkout** — because
this repo is unusual: the working tree *is* the deployment target. The runbook is
explicit — "Run commands from `/home/drdavient/docker`" (`docs/runbooks/stabilisation.md:3`)
— and `docker compose` runs in-place against in-tree files, against one host daemon.
Deployment is not a push/pull pipeline; it is in-place Compose on the host. (`origin`
*does* exist — `git@github.com:drdavient/bumblebeam.git`, fetch + push — but pushing is
orthogonal to the deploy protocol; agent-session SSH access may vary.)

**Deploy is serial by design.** Two agents can reason and edit in parallel, but they
share one daemon, one set of host ports, and one set of Docker networks — so production
change is serialized and auditable, not concurrent. Sell this as a **safety rail**, not
a throughput multiplier.

Verified against the repo, with the runtime-collision surface enumerated (all singletons
on one daemon — which is *why* deploys are serial):

- **Every service (and sub-service) pins an explicit `container_name`** (`portal`,
  `traefik`, `homeassistant`, `plex`, `gluetun`, `n8n`, `deluge`, `radarr`, `sonarr`,
  `prowlarr`, `flaresolverr`, `structurizr-lite`, `mount-rebooter`,
  `elements-waiter`, `mount-waiter`, `cloudflare-ddns`). This is a **passive backstop,
  not a safety boundary**: a stray `docker compose up` from a worktree can't spawn a
  clean parallel *duplicate* stack, but it may still conflict with, disrupt, or
  **recreate** the live containers. The real technical boundary is Docker-socket
  authority (see enforcement layers below).
- **Fixed host ports**: `80/443` (`traefik/`), `8181` (`structurizr-lite/`), `8123`
  (`HomeAssistant/`), and the media set published on **gluetun** —
  `8888/8989/7878/8112/8191/9696`. Because the `*arr`/deluge apps run
  `network_mode: container:gluetun`, their ports live on gluetun, so cycling gluetun
  cycles them all. Plus `network_mode: host` (`HomeAssistant/`, `plex/`).
- **Networks are owned by exactly one Compose stack** (not standalone-provisioned);
  dependent stacks consume the relevant shared networks `external: true`. Each is
  compose-managed (`driver`/`driver_opts`/`ipam`) in its owner — `gluetun-net` owned by
  `Home_Media/` and consumed externally by `traefik/`; `traefik-net` + `host-services-net`
  owned by `traefik/` (`host-services-net` is Traefik-only). `docker compose up` of the
  owner creates the network. **No provisioning tooling is needed; the empty
  legacy `ops/networks/` should be deleted.** The real constraint is **deploy ordering**
  (below).
- **`ops/` already exists** (`ops/backup/`) with a firm script convention to reuse:
  `#!/usr/bin/env bash`, `set -Eeuo pipefail`, `SCRIPT_DIR=$(cd -- … && pwd)` /
  `ROOT_DIR=$(cd -- … && pwd)`, a `log()` helper (`ops/backup/backup.sh`).

Net: **git isolation and runtime isolation are separate problems.** Worktrees solve the
first. The second is serial by nature of one host / one daemon / pinned singletons. This
plan codifies the split into three artifacts so any harness picks up the rule.

```
 EDIT (isolated, parallel)                DEPLOY (serial, one path — by design)
 ┌────────────────────┐
 │ ../docker-agentA    │  branch agent/a  ┐
 │  edits portal/, n8n/│  disjoint,       │ rebase + merge
 │  config --quiet ok  │  coupling-aware  │ sequentially
 └────────────────────┘                  ├──► /home/drdavient/docker  ──► ops/deploy/deploy.sh <svc>
 ┌────────────────────┐                  │    (canonical .git DIR,        │ clean-tree + on-main gate
 │ ../docker-agentB    │  branch agent/b  │     not a worktree)            │ flock -w .deploy.lock
 │  edits HomeAssistant│                  ┘                                │ config --quiet → up -d
 │  never `up` here    │                                                   ▼
 └────────────────────┘                              one daemon · pinned names · host ports
   worktree .git = FILE ──► deploy guard refuses     socket authority = only real boundary
                                                      owner-before-consumer deploy ordering
```

## Enforcement — three layers (name which is which)

1. **`ops/deploy/deploy.sh` is the mandatory operational path.** Its guard + lock
   reliably serialize everyone who uses it — a technical control **scoped to compliant
   callers**.
2. **Pinned `container_name`s on one daemon are a passive backstop** — they prevent a
   clean parallel *duplicate* stack, but an unsanctioned command may still conflict
   with, disrupt, or **recreate** the live containers; it does not reliably "fail
   loudly." That is precisely why the wrapper protocol matters. They are **not** a
   boundary.
3. **Docker-socket authority is the only real technical boundary.** Nothing stops a
   privileged direct Docker invocation. If strict enforcement ever matters, move deploy
   authority behind a dedicated host service/account — *not* shell conventions. (Out of
   scope for v1; named as the upgrade path.)

## Deliverables

### 1. ADR `docs/adr/0004-concurrent-agent-workflow.md`
Match the existing ADR shape (`# ADR 0004: …`, `- Status: accepted`, `- Date:
2026-07-13`, `## Decision`, `## Consequences` — see `0003`). Capture:
- **Edit in isolation, deploy in serial.** Worktree-per-agent off `main` on its own
  `agent/<x>-<task>` branch; agents edit service directories that are **disjoint *and*
  respect runtime-coupling clusters** (below) — directory-disjointness alone is not
  enough.
- **The three enforcement layers** above — especially that the wrapper protects
  compliant callers only and socket authority is the real boundary.
- **`traefik/` and `Home_Media/` are global resources** (they own the shared networks) —
  reserved to at most one agent/owner, redeployed only when nothing else is mid-deploy.
- **Deploy ordering after Docker-state loss, explicit network removal, or a prune of
  unused networks**: redeploy the **owning** stack first — `Home_Media` (`gluetun-net`),
  then Traefik and its
  consumers. A consumer brought up before its owner fails "network … not found." Do
  **not** manually recreate compose-managed networks or add network-creation tooling.
- **Deploys run only from the canonical checkout** `/home/drdavient/docker`, one at a
  time, under the **repository deploy lock** (`flock` on `.deploy.lock`, which
  serializes wrapper callers — deliberately *not* host-wide enforcement), via
  `ops/deploy/deploy.sh`. Never `up` from a worktree.
- **Merge sequentially**, rebasing each branch on `main` first; disjoint dirs keep
  merges clean except shared docs (`docs/task-register.md`, ADRs) — serialize those.
- **Backup gate = operator policy, not automated enforcement.** Require a **verified
  host-side Restic snapshot before the session's first *stateful* live deploy**
  (`ops/backup/backup.sh --consistent`), with an explicit exception for
  non-stateful/documentation-only deploys. Do **not** claim `ops/deploy` verifies this —
  it does not (today).
- **Elements mount health is verified host-side.** The agent sandbox sees `/mnt/Elements`
  read-only by design; `rw` status must be attributed to recorded host evidence
  (`findmnt` + backup/check/restore output), not inferred from a sandbox view.

### 2. `ops/deploy/deploy.sh` — flock wrapper with guards
New executable, reusing the `ops/backup/*.sh` idiom. Path is `ops/deploy/deploy.sh` to
match `ops/<area>/<script>.sh`. **CLI: `ops/deploy/deploy.sh [--allow-dirty] <service>`.**
Behavior:
1. Header exactly as the backup scripts: `#!/usr/bin/env bash`, `set -Eeuo pipefail`,
   `SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)`,
   `ROOT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)` *(two `..` — `ops/deploy/` sits two
   levels below the repo root, the same depth as `ops/backup/`; a single `..` would
   resolve to `…/docker/ops` and mis-target the guard, lock, and path checks)*, `log()`.
2. **Refuse to run from a worktree** (defense-in-depth on the sanctioned path). A
   `git worktree` checkout has `.git` as a *file*; the canonical checkout has it as a
   *directory*: `[[ -d "$ROOT_DIR/.git" ]] || { log "ERROR: deploy only from the
   canonical checkout, not a worktree"; exit 2; }`. (This guards the wrapper, not the
   daemon — see enforcement layer 3.)
3. **Parse `[--allow-dirty]` first, before resolving the service arg**, then **require
   canonical `main` + a clean tracked tree.** Refuse to deploy a half-finished checkout
   so "running system ⇔ reviewable commit on `main`" holds. `--allow-dirty` is a loud,
   logged **operator override for incident recovery** — explicitly *not* an
   access-control boundary (it cannot prove a human, not an agent, invoked it).
4. **Resolve the service arg safely.** Require exactly one remaining (non-flag) arg;
   `realpath` the compose file and require the **resolved** path to be **contained under
   `$ROOT_DIR`** via a **path-boundary check on the realpath result** — not a raw string
   prefix (which would accept e.g. `…/docker-evil/…`). Block `ops/deploy ../somewhere`;
   error if the compose file is missing. Deploy with `--project-directory` set to the
   compose file's directory. Prefer this over a hard-coded service-name allowlist so
   nested/renamed projects don't fossilise today's layout.
5. **Validate then deploy under one lock**, using a **file-descriptor `flock` with a
   timeout** so context/quoting stay clear and a wedged deploy fails loudly instead of
   blocking the other agent forever:
   ```sh
   exec {lock_fd}>"$ROOT_DIR/.deploy.lock"
   flock -w 300 "$lock_fd" || { log "ERROR: another deploy holds the lock"; exit 3; }
   docker compose --project-directory "$svc_dir" -f "$compose" config --quiet
   docker compose --project-directory "$svc_dir" -f "$compose" up -d
   ```
   The invariant: **`config --quiet` and `up -d` run inside the same lock.** `flock`
   auto-creates the lock file.
6. `chmod +x ops/deploy/deploy.sh`; add `/.deploy.lock` to `.gitignore` (runtime
   artifact, consistent with "runtime state stays out of Git").

### 3. AGENTS.md + task register
Edit `.agents/AGENTS.md` (the single source of truth; `CLAUDE.md`/`AGENTS.md` are shims
— do not touch those). Matching the file's voice:
- A **Ground rules** bullet (alongside "Validate before committing or deploying"):
  *"Concurrent agents edit in isolated worktrees but deploy serially from the canonical
  checkout via `ops/deploy/deploy.sh` — never `docker compose up` from a worktree. The
  wrapper serializes compliant callers; the only real boundary is Docker-socket
  authority. See `docs/adr/0004-concurrent-agent-workflow.md`."*
- A brief **## Concurrent agents** section pointing at ADR 0004 and the deploy wrapper.

Also add a row to `docs/task-register.md` recording this decision (Done, evidence → ADR
0004 + `ops/deploy/deploy.sh`), per the repo's decisions-as-records convention.

### 4. Delete the legacy `ops/networks/`
Remove the empty, untracked `ops/networks/` directory — it is not a provisioning gap;
networks are Compose-owned (see Context).

## Order of work
1. Write ADR 0004 (the decision of record).
2. Add `ops/deploy/deploy.sh` + `.gitignore` entry (the enforcement).
3. Edit `.agents/AGENTS.md` + `docs/task-register.md` (the pointers).
4. Delete the legacy `ops/networks/`.

## Verification
- **Worktree edit isolation:** `git worktree add ../docker-agentA -b agent/a-test`; edit
  a file in each of canonical + worktree; `git worktree list` shows both and neither sees
  the other's uncommitted changes.
- **Validation still works from a worktree:** inside `../docker-agentA`, `docker compose
  -f portal/compose.yml config --quiet` exits 0.
- **The worktree guard fires:** run `ops/deploy/deploy.sh portal` from `../docker-agentA`
  → exits 2 (`.git` is a file there). Run `ops/deploy/deploy.sh nope` from canonical →
  non-zero, missing-compose error. Run it with a dirty tree → refused unless
  `--allow-dirty`.
- **Arg resolution is safe:** `ops/deploy/deploy.sh ../etc` (or any path resolving
  outside `$ROOT_DIR`) → refused.
- **The lock serializes — WITHOUT deploying** (never live-deploy just to test a lock):
  hold `.deploy.lock` in one shell (`exec {fd}>… ; flock "$fd"`), then in a second shell
  attempt the lock with **either** `flock -n` (expect immediate failure) **or**
  `flock -w 1` (expect a timed wait, then failure) — these are mutually exclusive modes,
  don't combine them — and confirm it does not acquire the lock. Then rely on **code
  inspection** to confirm `config` and `up -d` sit inside the locked section. Reserve
  live deployment for a real, independently justified change.
- **Deploy ordering:** do **not** prove this by pruning/removing networks or bringing up
  `Home_Media` on Bumblebeam. Instead, **document** the owner-first recovery order (owner
  `Home_Media` → `gluetun-net`, then Traefik + consumers) and **validate the stacks
  render** (`docker compose … config --quiet`). Exercise the actual network-loss ordering
  only on a **disposable Docker daemon**.
- **Cleanup:** the worktree test edits files, so first **revert the deliberate test
  edits in both trees** (`git -C . checkout -- <file>` in the canonical checkout and
  `git -C ../docker-agentA checkout -- <file>` in the worktree) — otherwise
  `git worktree remove` refuses on a dirty tree — then remove the worktree and branch:
  `git worktree remove ../docker-agentA && git branch -D agent/a-test`.
- **Elements mount:** capture host-side `findmnt /mnt/Elements` (expect `rw` on the host)
  as recorded evidence; do not rely on the sandbox's read-only view.
- **Docs/lint:** `docker compose -f portal/compose.yml config --quiet` still passes
  post-edit; ADR 0004 follows the 0003 heading structure; no secrets/runtime values in
  Git (`git status --short --ignored`).

## Notes / constraints
- No compose files change — this is workflow tooling + docs only; existing services are
  untouched.
- `ops/deploy/deploy.sh` intentionally does **not** merge or rebase; that stays a
  human/agent step so the deployer sees conflicts (esp. shared docs) before anything goes
  live.
- `origin` exists (`git@github.com:drdavient/bumblebeam.git`); pushing is orthogonal to
  the local worktree/deploy protocol and agent-session SSH access may vary. The protocol
  is local-first (worktrees, branches, merge to `main`).
