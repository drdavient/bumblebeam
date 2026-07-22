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

## Amendment (2026-07-22): doctrine-only delivery, monitored, with an escalation ladder

**Measured evidence.** Headless claude-code trials (fresh sessions, realistic
first tasks, tool calls parsed from transcripts) showed the delivery mechanism
matters and prose wording is load-bearing:

- SessionStart hook (test fixture): report present in context before the first
  prompt, 1/1, zero model judgment involved.
- Doctrine, original wording ("claude-code receives the report automatically…"):
  **0/3** ran preflight — the rule was verifiably loaded and quotable, but the
  "automatic" clause gave sessions a skip excuse.
- Doctrine, reworded as an unconditional first-action imperative: **3/3**, with
  preflight as the first tool call every time.

**Decision.** Ship doctrine-only delivery (the layer-2 hook is designed but *not
installed*), and make compliance and drift observable instead of assumed:
`preflight.sh` appends one line per run to a gitignored `runs.log` beside the
script — timestamp, `source=` (`manual`/`hook`/`cron`), branch, findings count,
finding keys. Review the log when working the register; each rung below is
implemented only when its trigger fires (YAGNI — every deferred design stays
recorded here).

| Rung | Trigger (from `runs.log` / transcripts) | Deferred design |
|---|---|---|
| 1. Daily cron baseline | Any anomaly key persisting > 7 days unremediated, or a 14-day gap in runs despite active sessions | systemd timer running `preflight.sh --source=cron` daily: drift detection independent of agent behaviour |
| 2. SessionStart hook | Two sessions in 30 days observed skipping preflight, after one wording tune has been tried | The layer-2 hook from this ADR, added to `.claude/settings.json` (owner edit — the harness classifier blocks agents from writing hook config): `hooks.SessionStart`, matcher `startup\|resume\|clear`, command `[ -x "$CLAUDE_PROJECT_DIR/.agents/skills/preflight/preflight.sh" ] && bash "$CLAUDE_PROJECT_DIR/.agents/skills/preflight/preflight.sh" \|\| true`, timeout 10. Deterministic delivery — but **claude-code only**: this is a multi-harness system, so other harnesses (codex, …) remain on doctrine + monitoring whatever this rung does |
| 3. Eval harness | Wording tunes fail twice to restore compliance | ~10 realistic prompts (train/holdout split) + a scorer parsing headless-session transcripts for compliance predicates — the measurement rig from the 2026-07-22 trials, formalised |
| 4. SkillOpt | Eval-driven manual tuning stalls | [microsoft/SkillOpt](https://github.com/microsoft/SkillOpt) (MIT): validation-gated text-space optimization of a **bounded artifact only** (the preflight rule or SKILL.md, never whole-file AGENTS.md — reward-hacking risk against unmeasured safety rules). Cheap inner-loop rollouts on a local model (LM Studio on Ultra-Magners / Ollama on Bumblebeam as a tracked Compose stack, LAN-only); acceptance gate = small claude-code holdout on the real harness; adoption PR-gated |

Rungs are ordered by cost and escape earlier rungs' failure modes; the hook
(rung 2) permanently solves *delivery*, so rungs 3–4 exist only for *content*
quality problems the hook cannot fix.
