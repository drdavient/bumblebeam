# ADR 0002: agent configuration and memory standard

- Status: accepted
- Date: 2026-07-12

## Decision

Standardise every AI coding harness (claude-code, codex, opencode, gemini-cli,
grok-cli, and any added later) around a single, vendor-neutral source of truth.

- **Canonical shared instructions** live at `.agents/AGENTS.md`; **canonical shared
  skills** live under `.agents/skills/`. `.agents/` is the harness-agnostic agent
  root.
- Each harness reaches the canonical instructions through a **thin shim** at the
  path it natively reads, never a second copy:
  - claude-code: `CLAUDE.md` containing `@.agents/AGENTS.md` (native import);
  - codex and other AGENTS.md-native harnesses: a relative symlink `AGENTS.md` →
    `.agents/AGENTS.md` at the repo root (the AGENTS.md convention defines no
    include directive, so a symlink is used);
  - future harnesses: one pointer at whatever path they read, back into `.agents/`.
- Shared skills live at `.agents/skills/`, read **natively by codex** (plus legacy
  `.codex/skills`) and reached by claude-code via a relative symlink `.claude/skills`
  → `../.agents/skills`.
- Only genuinely **tool-native** configuration lives under a harness's own directory
  (`.claude/settings.json`; global `~/.codex/config.toml`). Credential, session,
  history, and cache state is never committed (`.codex/` stays git-ignored).
- Onboarding and initialisation are performed by two **global** skills, installed
  under `~/.agents/skills/` (surfaced to claude-code via `~/.claude/skills/*`
  symlinks and to codex via `~/.codex/skills/*`), so they are available in every
  project:
  - **`/onboard`** — the single entry point; wires a harness into a project's
    `.agents/` standard and runs `/bootstrap` first when the project has none.
  - **`/bootstrap`** — establishes/extends `.agents/AGENTS.md` (the `/init` job),
    **idempotently and without clobbering** existing content.
- We deliberately do **not** override the built-in `/init` (though project skills can
  shadow built-ins): the entry point is explicit (`/onboard`), and a one-line
  context-guard in `.agents/AGENTS.md` handles a reflexive `/init` by forbidding a
  standalone `CLAUDE.md`.

### Commit vs ignore

Version the project's AI behaviour and shared development environment; do not
version personal, machine-specific, or session state. If it describes the project or
its shared dev environment, commit it; if it describes you, your machine, or the
current session, don't.

### Memory

Harness memory is **private working memory** — never shared, never committed. When a
memory becomes durable, reusable, and generally useful, promote the *knowledge* (not
the memory file) into versioned guidance: project-scoped knowledge into
`.agents/AGENTS.md`/`docs/`; cross-project knowledge into the system-level
`AGENTS.md`.

## Consequences

- One source of truth; no drift between per-harness instruction copies.
- Adding a harness is a bounded, repeatable step (`/onboard`), not bespoke work.
- The onboarding/init skills are global (machine-level), so a fresh clone on another
  machine does not carry them; they are installed once per machine.
- Relies on Git-tracked relative symlinks — fine on this Linux host; a Windows
  checkout would need `core.symlinks`. If Windows is ever required, invert so the
  real file sits at the natively-read path and `.agents/AGENTS.md` becomes the
  symlink.
- `.agents/AGENTS.md` is not discovered natively by any harness; the shims are
  mandatory and must be verified when a harness updates its discovery rules.

## Deferred / optional

- Per-service nested `AGENTS.md` + `CLAUDE.md` shim pairs, added only where a service
  needs bespoke guidance.
- Confirming/firming up the shim rows for opencode, gemini-cli, and grok-cli in the
  `/onboard` reference table as those harnesses are actually adopted.
