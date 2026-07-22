# Structurizr workspace sources

The DSL sources for the workspaces published to **Structurizr Server**
(ADR 0015). Structurizr Lite itself was retired on 2026-07-22 after the Server
handover passed owner acceptance; this directory keeps its name to preserve
history and references.

- `workspace/workspace.dsl` — the Bumblebeam architecture (Server workspace 1).
  Its `!docs` pages live in `workspace/docs/`; its `!decisions` import the
  repo's real `docs/adr/` directory.
- `archive/minecraft-quark-server.dsl` — the Minecraft Quark server model
  (Server workspace 2).

Publish changes with:

```sh
structurizr-server/publish.sh 1 structurizr-lite/workspace/workspace.dsl
structurizr-server/publish.sh 2 structurizr-lite/archive/minecraft-quark-server.dsl
```

`workspace/workspace.json` and `**/.structurizr/` are generated runtime state
and intentionally gitignored. Keep the model aligned with Compose and ADRs when
services or network boundaries change.
