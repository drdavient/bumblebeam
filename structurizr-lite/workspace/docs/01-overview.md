# Bumblebeam

The home-infrastructure host at `192.168.1.15`: declarative Compose stacks behind
a Traefik reverse proxy, with the HOME_MEDIA group isolated inside Gluetun's VPN
network namespace (every outbound media test must traverse it — ADR 0007).

- **Source of truth:** the [bumblebeam repository](https://github.com/drdavient/bumblebeam)
  — Compose stacks, runbooks, task register, and the ADRs imported as this
  workspace's decision log.
- **Naming:** real hosts are `*.home.arpa`; reverse-proxied applications are
  `*.svc.home.arpa` (wildcard to Bumblebeam, ADR 0003).
- **Remote access:** Tailscale subnet router + split DNS + on-demand exit node
  (ADR 0009); nothing is exposed to the public internet except the Cloudflare
  n8n route.
- **Data boundary:** secrets, databases, and runtime state live in the encrypted
  Restic backup, never Git (see `docs/inventory.md` in the repo).

This workspace is published to Structurizr Server by
`structurizr-server/publish.sh`, which renders the versioned DSL to workspace
JSON (ADR 0015).
