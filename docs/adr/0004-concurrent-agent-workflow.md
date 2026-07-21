# ADR 0004: concurrent-agent workflow

- Status: accepted
- Date: 2026-07-14

## Decision

Adopt a minimal operating protocol for running concurrent AI agents against this
repository and its host. Codify the decisions now; defer the enforcement tooling until
measured triggers fire (see Escalation below).

- **One deployer per host.** Many agents may research, review, plan, or make isolated
  edits, but exactly one **lead agent** owns the canonical checkout, merges work, and is
  the only one permitted to make a live Docker deployment.
- **Deploy is serial and canonical.** All live deploys run from
  `/home/drdavient/docker` — never `docker compose up` from a worktree. Editing may be
  parallel (branch/worktree) when genuinely useful; merge and deploy are serial.
- **This is a convention, not a boundary.** Anyone with Docker-socket authority can
  bypass it; socket authority remains the real technical boundary. If strict enforcement
  ever matters, the durable answer is a dedicated deploy service/account — not shell
  conventions.
- **Backup gate = operator policy.** Before the first actual Docker deployment in a
  maintenance session, run `ops/backup/backup.sh --consistent` and confirm it succeeds.
  Documentation-only work needs no backup; do not repeat the snapshot for further deploys
  in the same maintenance session. Once scheduled backups are proven reliable, a
  successful backup within the last 24 hours satisfies this gate. A maintenance session
  is one continuous, related change window; it ends when work is handed off or paused.
- **Network deploy-ordering (recovery knowledge).** Networks are owned by exactly one
  Compose stack (dependent stacks consume shared networks `external:`;
  `host-services-net` is Traefik-only). After Docker-state loss, explicit network
  removal, or a prune of unused networks, redeploy the **owning** stack first —
  `Home_Media` (`gluetun-net`), then Traefik and its consumers. Do not manually recreate
  compose-managed networks or add network-creation tooling.
- **Partition along runtime-coupling clusters, not bare directories.** Traefik-fronted
  services depend on `traefik-net` + a running `traefik`; all `Home_Media` apps couple
  through gluetun (`network_mode: container:gluetun`), so `Home_Media` is one indivisible
  owner. `traefik/` and `Home_Media/` are global resources, reserved to one owner.
- **Elements mount evidence is host-side.** The agent sandbox sees `/mnt/Elements`
  read-only by design; `rw` status must be attributed to recorded host evidence
  (`findmnt` + backup/check/restore output), not a sandbox view.

## Day-to-day workflow

1. Use one lead agent for ordinary changes in `/home/drdavient/docker`.
2. Use a branch/worktree only when a second agent has a genuinely independent editing
   task; most changes stay single-agent in the canonical checkout.
3. The lead agent reviews and merges that work into the canonical checkout.
4. Satisfy the **backup gate**: before the maintenance session's *first* stateful deploy,
   run `ops/backup/backup.sh --consistent` and confirm success — or, once scheduled
   backups are proven reliable, rely on a successful snapshot within the last 24 h. Then
   run the stabilisation checks.
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

No standalone deploy helper is introduced: a one-line helper is the thin end of the
deferred wrapper, carrying its own interface, maintenance, and exception handling. The
reproducibility benefit lives as the explicit manual checks in step 5, so Phase 0 stays
pure convention.

## Escalation (metric-driven)

The full enforcement design — `ops/deploy/deploy.sh` (realpath path-boundary check, fd
`flock -w`, clean-tree + worktree guards), `/.deploy.lock` in `.gitignore`, and its
non-destructive verification — is pre-designed and reviewed in
`docs/concurrent-agent-workflow-plan-v1.md`. It is deferred until a trigger fires. Track
these cheaply (one line per event in the tally below) and step up to v1 when **any**
trigger is met:

| Trigger | Metric to watch | Threshold → escalate | How we log it |
|---|---|---|---|
| High concurrency | Max agents writing to this repo at the same time | **≥ 3 concurrent writers** | one line when a 3rd writer joins |
| Deploy near-miss | Worktree/direct `up`, or a live container unintentionally recreated/disrupted | **≥ 1 (any)** — immediate | incident line: what happened |
| Second operator | Humans with host/deploy access | **> 1** — immediate | note who + when access granted |
| Coordination cost | Merge/deploy coordination causing delay or error | **≥ 2 in a rolling 90 days** | one line per incident |

Two concurrent writers is the case this protocol is designed for, not a failure. The
concurrency trigger is a *third* simultaneous writer, where lead-agent merge coordination
starts to strain.

When a threshold is hit, use `docs/concurrent-agent-workflow-plan-v1.md` as the
implementation reference and **amend this ADR** with the enforcement details (do not
create a new ADR). The metric that fired becomes that amendment's justification.

### Escalation tally

| Date | Trigger | Event |
|---|---|---|
| 2026-07-21 | Coordination cost (1 of 2 in 90 days) | Week-long drift discovered during commit sweep: seven uncommitted workstreams, one deployed stack (`video/`) with no repo presence, one running container (`readyroom-bot`) unknown to the repo, stale task register. Response: layered session/commit enforcement (ADR 0012), which is *complementary* to — not an escalation of — this ADR's deferred concurrency tooling. |

## Consequences

- There is always a clear deployment owner, which is the largest safety gain for a
  single-daemon host with fixed `container_name`s, shared host ports, host-networked
  services, and Gluetun-coupled media.
- Concurrent editing in isolated branches/worktrees is supported; only merge and deploy
  are serialised.
- No new operational surface is added today: no `ops/deploy/`, no lock file, no guard
  tooling. Escalation is objective and pre-designed rather than discretionary.
- The convention does not replace security/recovery controls and does not pretend to be a
  technical boundary; Docker-socket authority remains the real one.
