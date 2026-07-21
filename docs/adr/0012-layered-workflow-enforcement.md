# ADR 0012: layered workflow enforcement

- Status: accepted
- Date: 2026-07-21

## Context

A week of work drifted despite the workflow being written in `.agents/AGENTS.md`:
seven uncommitted workstreams, one deployed stack (`video/`) with no repo presence,
one running container (`readyroom-bot`) unknown to the repo, and a stale task
register — all discovered only by a manual sweep. Prose is doctrine, not process:
an instruction file influences behaviour but neither observes state nor gates
actions. The question was how to make the workflow *checkable* without building the
enforcement tooling ADR 0004 deliberately deferred.

## Decision

Three layers, each catching what the previous cannot; determinism only where git
itself can enforce it.

1. **`/preflight` skill — a checkable procedure.**
   `.agents/skills/preflight/preflight.sh` is the *single implementation* (the
   same idiom as the agents repo's `wire-machine.sh`: the SKILL.md delegates to
   the script and never restates its logic). It reports anomalies only — unpushed
   commits, untracked compose stacks, running containers named in no tracked
   compose file, an unwired commit gate — and always exits 0. It is read-only:
   it never fixes anything.

2. **SessionStart hook — mechanical context injection (claude-code).**
   A `hooks.SessionStart` entry in the committed `.claude/settings.json`
   (matchers `startup|resume|clear`) runs the script and **injects its stdout into
   the model's context before the first prompt**. The report therefore reaches a
   claude-code agent with no prose compliance required. It cannot block a session;
   the command is existence-guarded, `|| true`d, capped at 10 s, and the script
   internally wraps `docker ps` in `timeout 5`. Harnesses without an equivalent
   hook (codex) rely on the session-start rule in `.agents/AGENTS.md`.

3. **Versioned pre-commit gate — deterministic.**
   `ops/git-hooks/pre-commit` is versioned; one per-clone command —
   `git config core.hooksPath ops/git-hooks` — makes git run it on **every**
   `git commit` by any process (human, any harness, cron), aborting on non-zero
   exit. It checks *staged files only*: each staged `*compose*.yml` must pass
   `docker compose config --quiet`, and staged additions are scanned with
   high-precision secret patterns (key headers, quoted credential literals;
   `${VAR}` interpolations exempt). Doc-only commits trigger zero compose
   renders. Worktrees share `.git/config`, so one wiring covers concurrent-agent
   worktrees. The only bypass is `git commit --no-verify`, which
   `.agents/AGENTS.md` forbids — the threat model is drift and accident, not
   malice. Preflight warns when a clone is unwired, and the project scope of the
   global `/onboard-harness` skill wires it, so fresh clones self-heal.

## Boundary with ADR 0004

ADR 0004 defers *concurrency* enforcement (deploy serialization, locks) behind
metric triggers, and that deferral stands — this ADR adds none of it. These layers
address a different failure class: session-start *awareness* and commit
*validity*. The 2026-07-21 drift event is logged in ADR 0004's escalation tally as
a coordination-cost data point, not a trigger firing.

## Consequences

- claude-code sessions start with a mechanical state report; no memory or
  discipline required. Other harnesses still depend on the auto-loaded imperative
  (accepted residual risk, stated here).
- Invalid compose changes and pattern-matching secrets cannot be committed from a
  wired clone, by any process.
- `core.hooksPath` is per-clone state (lives in unversioned `.git/config`), so a
  fresh clone starts unwired — mitigated by the preflight warning and
  `/onboard-harness`.
- The semantic gap remains honest: a stale register row is a definition-of-done
  duty; preflight surfaces only the mechanical signals (exactly the ones that
  caught `video/` and `readyroom-bot`).
