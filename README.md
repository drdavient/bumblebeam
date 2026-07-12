# Bumblebeam home infrastructure

Declarative configuration, operational scripts, runbooks, architecture decisions,
and recovery evidence for the services hosted on Bumblebeam (`192.168.1.15`).

The canonical LAN namespace is `service.home.arpa`. `service.svc.home.arpa` is a
temporary compatibility alias, and bare hostnames are retained for convenient LAN
clients.

Runtime databases, plaintext secrets, certificates, logs, caches, downloads, Plex
metadata, and bulk media are intentionally excluded from Git. They belong in the
encrypted Restic backup or are explicitly classified as reproducible/bulk data.

Start with [the stabilisation runbook](docs/runbooks/stabilisation.md) and keep
[the task register](docs/task-register.md) current as checks are completed.
