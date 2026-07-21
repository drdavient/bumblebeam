# ADR 0002: agent configuration and memory standard

- Status: moved (2026-07-21)
- Date: 2026-07-12

## Decision

Moved: this standard is cross-project and now lives in the standalone agents repo as
[ADR 0001](https://github.com/drdavient/agents/blob/main/docs/adr/0001-agent-configuration-and-memory-standard.md)
(cloned locally at `~/.agents`). In one line: one vendor-neutral source of truth per
project (`.agents/AGENTS.md` + `.agents/skills/`), thin per-harness shims, wired by
the global `/onboard-harness` skill.
