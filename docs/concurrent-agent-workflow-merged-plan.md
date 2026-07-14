# Concurrent agents on Bumblebeam — phased plan (adopt minimal now, escalate on metrics)

## Decision for review

Go forward **today** with the minimal operating protocol, and **codify the decisions
now** — but defer the enforcement tooling until measured triggers say we need it. This
merges the minimal plan (archived under `docs/archive/concurrent-agent-workflow/`) and
the full design (`concurrent-agent-workflow-plan-v1.md`) by splitting v1 into two piles:

- **Knowledge (ship now)** — the decisions of record, which have *zero* operational
  surface and match the repo's "codify decisions as ADRs" ethos.
- **Enforcement (defer)** — the `ops/deploy` wrapper, lock, guards, and test regimen,
  which are real, permanent surface. Build them when concrete metrics cross a threshold.

Rationale: Bumblebeam has one live Docker daemon, fixed `container_name`s, shared host
ports, host-networked services, and Gluetun-coupled media — so it needs **one deployer
per host** regardless of how many agents edit Git. The largest safety gain is a clear
deployment owner, which a convention captures for free. v1's own conclusion is that
**Docker-socket authority is the only real technical boundary** — the wrapper can't beat
a direct socket call — so its value is convenience/defense-in-depth, not a boundary, and
is not yet worth the surface for a single operator.

---

## Phase 0 — adopt today (this plan's deliverables)

### D1. ADR `docs/adr/0004-concurrent-agent-workflow.md` — decisions only, lightweight
Match the `0003` shape (`# ADR 0004: …`, `- Status: accepted`, `- Date: 2026-07-13`,
`## Decision`, `## Consequences`). Record the **decisions and operational knowledge**,
explicitly *without* mandating tooling yet:

- **One deployer per host.** Many agents may research, review, plan, or make isolated
  edits; exactly one **lead agent** owns the canonical checkout, merges work, and is the
  only one permitted to make a live Docker deployment.
- **Deploy is serial and canonical.** All live deploys run from `/home/drdavient/docker`
  (never `docker compose up` from a worktree). Editing may be parallel (branch/worktree)
  when genuinely useful; merge and deploy are serial.
- **This is a convention, not a boundary.** Anyone with Docker-socket authority can
  bypass it; socket authority remains the real technical boundary. If strict enforcement
  ever matters, the durable answer is a dedicated deploy service/account — not shell
  conventions.
- **Backup gate = operator policy.** Before the first actual Docker deployment in a
  maintenance session, run `ops/backup/backup.sh --consistent` and confirm it
  succeeds. Documentation-only work needs no backup; do not repeat the snapshot for
  further deployments in the same maintenance session. Once scheduled backups are
  proven reliable, a successful backup within the last 24 hours satisfies this gate.
  A maintenance session is one continuous, related change window; it ends when work is
  handed off or paused.
- **Network deploy-ordering (recovery knowledge).** Networks are owned by exactly one
  Compose stack (dependent stacks consume shared networks `external:`; `host-services-net`
  is Traefik-only). After Docker-state loss, explicit network removal, or a prune of
  unused networks, redeploy the **owning** stack first — `Home_Media` (`gluetun-net`),
  then Traefik and its consumers. Do not manually recreate compose-managed networks or
  add network-creation tooling.
- **Partition along runtime-coupling clusters, not bare directories.** Traefik-fronted
  services depend on `traefik-net` + a running `traefik`; all `Home_Media` apps couple
  through gluetun (`network_mode: container:gluetun`), so `Home_Media` is one indivisible
  owner. `traefik/` and `Home_Media/` are global resources, reserved to one owner.
- **Elements mount evidence is host-side.** The agent sandbox sees `/mnt/Elements`
  read-only by design; `rw` status must be attributed to recorded host evidence
  (`findmnt` + backup/check/restore output), not a sandbox view.
- **Escalation is metric-driven** (see Phase 1). Reference
  `docs/concurrent-agent-workflow-plan-v1.md` as the pre-designed escalation.

### D2. `.agents/AGENTS.md` — ground rule + short section
Edit the single source of truth (not the `CLAUDE.md`/`AGENTS.md` shims). Add, in the
file's voice:
- A **Ground rules** bullet: *"Concurrent agents: many may edit in isolated
  branches/worktrees, but exactly one lead agent merges and deploys, serially, from the
  canonical checkout — never `docker compose up` from a worktree. This is a convention,
  not a boundary; Docker-socket authority is the real one. See
  `docs/adr/0004-concurrent-agent-workflow.md`."*
- A brief **## Concurrent agents** section pointing at ADR 0004 and the day-to-day
  workflow below.

### D3. `docs/task-register.md` — record the decision
Add a row (Done; evidence → ADR 0004) noting the minimal protocol is adopted and v1 is
the deferred, metric-triggered escalation.

### D4. Day-to-day workflow (in the ADR or AGENTS.md section)
1. Use one lead agent for ordinary changes in `/home/drdavient/docker`.
2. Use a branch/worktree only when a second agent has a genuinely independent editing
   task; most changes stay single-agent in the canonical checkout.
3. The lead agent reviews and merges that work into the canonical checkout.
4. Satisfy the **backup gate** (per D1): before the maintenance session's *first*
   stateful deploy, run `ops/backup/backup.sh --consistent` and confirm success — or,
   once scheduled backups are proven reliable, rely on a successful snapshot within the
   last 24 h. Then run the stabilisation checks.
5. **Pre-deploy reproducibility checks** (manual, no tooling) — confirm the canonical
   checkout is on `main` with a clean tracked tree and the target Compose renders,
   **before** `up -d`. This preserves "running system ⇔ reviewable commit on `main`"
   without adding an interface to maintain:
   ```bash
   test "$(git branch --show-current)" = main
   git diff --quiet && git diff --cached --quiet
   docker compose -f <svc>/compose.yml config --quiet
   ```
6. Deploy from the canonical checkout, verify the service, update the task register.

### D5. (Decided — no) standalone helper — use the manual checklist instead
A one-line helper is the thin end of the deferred wrapper: it would carry its own
interface, maintenance, and exception handling. The reproducibility benefit is still
worth having now, so it lives as the **explicit manual checks in D4 step 5**, not as
tooling. Phase 0 therefore stays pure-convention.

**Explicitly deferred in Phase 0:** `ops/deploy/deploy.sh`, the `flock` lock, the
worktree/`.git` guard, the `--allow-dirty` override, and the lock/guard test regimen —
all held in v1 until a trigger fires.

### D6. Delete the empty legacy `ops/networks/`
Untracked, empty, zero-risk housekeeping — not enforcement tooling, so there is no
reason to defer it. Remove it now; compose-managed networks are owned by their stacks
(see D1) and need no `ops/` provisioning.

---

## Phase 1 — escalate to v1 when metrics cross a threshold

Escalation is **not** a vibe; track these cheaply (a short tally in `docs/task-register.md`
or an ADR 0004 appendix — one line per event) and step up to v1 when **any** trigger is
met:

| Trigger | Metric to watch | Threshold → escalate | How we log it |
|---|---|---|---|
| High concurrency | Max agents writing to this repo at the same time | **≥ 3 concurrent writers** | one line when a 3rd writer joins |
| Deploy near-miss | Worktree/direct `up`, or a live container unintentionally recreated/disrupted | **≥ 1 (any)** — immediate | incident line: what happened |
| Second operator | Humans with host/deploy access | **> 1** — immediate | note who + when access granted |
| Coordination cost | Merge/deploy coordination causing delay or error | **≥ 2 in a rolling 90 days** | one line per incident |

Note: **two** concurrent writers is the case the minimal protocol is designed for, not a
failure — successful concurrent editing is fine. The concurrency trigger is a *third*
simultaneous writer, where lead-agent merge coordination starts to strain.

When a threshold is hit, use `concurrent-agent-workflow-plan-v1.md` as the
**implementation reference** (already reviewed and correction-complete): build
`ops/deploy/deploy.sh` (realpath path-boundary check, fd `flock -w`, clean-tree +
worktree guards), add `/.deploy.lock` to `.gitignore`, and run its non-destructive
verification. **Adapt v1's ADR step:** ADR 0004 already exists from Phase 0, so *amend*
it with the enforcement details rather than creating it again. The metric that fired
becomes that amendment's "Consequences" justification.

---

## Order of work (today)
1. Write ADR 0004 (D1) — the decision + operational knowledge.
2. Edit `.agents/AGENTS.md` (D2) + add the day-to-day workflow, including the manual
   pre-deploy reproducibility checks (D4).
3. Add the `docs/task-register.md` row and start the escalation tally (D3, Phase 1).
4. Delete the empty legacy `ops/networks/` (D6).

## Verification (today)
- **Docs are self-consistent:** ADR 0004 follows the `0003` structure; AGENTS.md ground
  rule + section cross-link the ADR; task register row present with the tally stub.
- **No tooling/state committed:** no `ops/deploy/`, no `.deploy.lock`; `git status
  --short --ignored` shows nothing secret/runtime added.
- **Housekeeping done:** empty `ops/networks/` is gone (`test ! -e ops/networks`).
- **Compose still renders** (sanity, since we touch no compose): `docker compose -f
  portal/compose.yml config --quiet` exits 0.
- **The escalation path is live:** confirm `concurrent-agent-workflow-plan-v1.md` is
  referenced from ADR 0004 as the triggered design, and the metric table is recorded.

## What this does and doesn't do
- **Does:** give a clear deployment owner today, capture all durable decisions and
  recovery knowledge now, and make escalation objective and pre-designed.
- **Doesn't:** replace existing security/recovery controls, and doesn't pretend a
  convention is a technical boundary. It defers only the concurrent-agent deployment
  *tooling* — nothing else.

## Source documents
- Full escalation design (reviewed, ready): `docs/concurrent-agent-workflow-plan-v1.md`
- Archived deliberation trail (original plan, both reviews, syntheses, minimal
  protocol): `docs/archive/concurrent-agent-workflow/`
