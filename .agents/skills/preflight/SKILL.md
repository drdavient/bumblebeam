---
name: preflight
description: >-
  Session-start anomaly report for this repo. Run at the start of every working
  session (claude-code gets it injected automatically via a SessionStart hook);
  then map each reported anomaly to its fix before starting new work.
---

# preflight

Surface repo/runtime drift at session start, before it compounds: unpushed or
uncommitted work, untracked Compose stacks, running containers no tracked compose
file names, and an unwired commit gate.

## Boundary

- **Owns:** read-only reporting of anomalies, and the interpretation table below.
- **Never:** fixes anything itself — no commits, no deploys, no config writes.
  Acting on findings is the session's (or lead agent's) job.

## Run it

[`preflight.sh`](preflight.sh) is the **single implementation** — execute the
file; never retype or paraphrase its checks:

```bash
bash .agents/skills/preflight/preflight.sh
```

It always exits 0 and prints either one `PREFLIGHT OK` line or a findings list.
claude-code sessions receive this output automatically (SessionStart hook in
`.claude/settings.json`); other harnesses run it per the session-start rule in
`.agents/AGENTS.md`.

## Interpreting findings

| Finding | Action |
|---|---|
| commits not pushed | Push when the owner asks; flag if they accumulate |
| behind upstream | `git fetch` + review before editing |
| working tree counts | Informational mid-work; commit per workstream before handoff |
| unregistered stack | Add the directory to Git + `docs/task-register.md` row (this caught `video/` on 2026-07-21) |
| unknown running container | Track it (compose file + register row) or record a decision for it (e.g. `readyroom-bot`) |
| git hooks unwired | Run the printed command: `git config core.hooksPath ops/git-hooks` |
| docker ps unavailable | Investigate the daemon before any deploy work |

## Related

- Commit gate: `ops/git-hooks/pre-commit` (wired via `core.hooksPath`)
- Decision: `docs/adr/0012-layered-workflow-enforcement.md`
