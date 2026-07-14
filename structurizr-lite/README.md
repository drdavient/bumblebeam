# Structurizr Lite

`workspace/workspace.dsl` is the sole tracked source for the Bumblebeam architecture
diagrams. Structurizr Lite generates `workspace/workspace.json` and `.structurizr/` at
runtime; both are intentionally ignored.

The workspace documents the live service topology, including the mandatory Gluetun VPN
boundary for HOME_MEDIA. Keep it aligned with Compose and ADRs when services or network
boundaries change.

The former Minecraft Quark server model is preserved at
`archive/minecraft-quark-server.dsl`. It is not mounted by the live viewer; move or copy
it into a dedicated Structurizr workspace only when that server's architecture is being
worked on.

Validate the Compose definition before deployment:

```sh
docker compose -f structurizr-lite/compose.yml config --quiet
```
