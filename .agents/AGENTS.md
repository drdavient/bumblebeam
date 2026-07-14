# Bumblebeam — agent instructions

Canonical, harness-agnostic instructions for any AI coding harness — claude-code,
codex, opencode, gemini-cli, grok-cli, or whatever comes next — working in this
repo. This file is the single source of truth. Every harness reaches it through a
thin shim at the path that harness natively reads; run the **`/onboard`** skill to
wire a new harness in.

## What this repo is

Declarative configuration, operational scripts, runbooks, architecture decisions,
and recovery evidence for the services hosted on Bumblebeam (`192.168.1.15`). See
`README.md` for the overview.

## Ground rules

- **LAN naming is split by role** (see `docs/adr/0003-host-and-service-namespaces.md`):
  real hosts use `host.home.arpa`; reverse-proxied applications use
  `service.svc.home.arpa`. DHCP advertises `svc.home.arpa`, so bare service names
  resolve for LAN convenience. Do not add per-service `*.home.arpa` records.
- **Never commit secrets or runtime state.** The data classification and Git
  boundary are defined in `docs/inventory.md`: secrets, databases, certificates,
  logs, caches, Plex metadata, and bulk media belong in the encrypted Restic backup
  (or are classified reproducible/bulk), never in Git.
- **Validate before committing or deploying.** For Compose changes run
  `docker compose … config --quiet`; follow `docs/runbooks/stabilisation.md`.
- **Adapt, don't replace.** Treat existing working configuration as evidence. Prefer
  extending the current state over starting again.
- **Concurrent agents:** many may edit in isolated branches/worktrees, but exactly one
  lead agent merges and deploys, serially, from the canonical checkout — never
  `docker compose up` from a worktree. This is a convention, not a boundary;
  Docker-socket authority is the real one. See
  `docs/adr/0004-concurrent-agent-workflow.md`.

## Where to start

- Runbook: `docs/runbooks/stabilisation.md`
- Task register (keep it current as checks complete): `docs/task-register.md`
- Decisions: `docs/adr/`

## Concurrent agents

One lead agent owns the canonical checkout at `/home/drdavient/docker`, merges others'
work, and is the only one that deploys — serially, from that checkout. Other agents may
edit in isolated branches/worktrees. Before a maintenance session's first stateful
deploy, satisfy the backup gate, then run the manual pre-deploy reproducibility checks
(on `main`, clean tracked tree, target Compose renders). This is a convention, not a
technical boundary; the enforcement tooling is pre-designed in
`docs/concurrent-agent-workflow-plan-v1.md` and deferred until metric triggers fire. Full
decisions, day-to-day workflow, and the escalation table:
`docs/adr/0004-concurrent-agent-workflow.md`.

## Project memory & decisions

Durable, project-scoped knowledge lives in **versioned guidance**, not in any
harness's private memory. Record decisions as ADRs under `docs/adr/` and ongoing
work in `docs/task-register.md`. The agent-configuration standard itself is
`docs/adr/0002-agent-configuration-and-memory-standard.md`.

## Memory policy

Treat each harness's memory as **private working memory** — never shared, never
committed. When a memory becomes durable, reusable, and generally useful, **promote
the knowledge** (not the memory file) into versioned guidance:

- project-scoped → this file / `docs/` (an ADR or the task register);
- cross-project / enduring → the **system-level `AGENTS.md`**.

## Configuration standard

- **This file is the source of truth. Do not generate a standalone `CLAUDE.md` (or
  other per-harness instruction copy) — harnesses reach this file through a thin
  shim.**
- Canonical shared instructions: **`.agents/AGENTS.md`** (this file).
- Canonical shared skills: **`.agents/skills/`** (read natively by codex; reached by
  claude-code via the `.claude/skills` symlink).
- Each harness gets a thin shim at the path it natively reads, pointing back here.
  Only genuinely tool-native config (auth, sandbox, model policy) lives under that
  harness's own directory, and credential/session state stays out of Git.
- Two global skills implement this standard (installed under `~/.agents/skills/`, so
  they surface in every project):
  - **`/onboard`** — wire a harness into this standard (the entry point; runs
    `/bootstrap` first if `.agents/AGENTS.md` is missing/empty).
  - **`/bootstrap`** — establish/extend `.agents/AGENTS.md`, idempotently and without
    clobbering existing content.
