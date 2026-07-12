# Bumblebeam home infrastructure

Declarative configuration, operational scripts, runbooks, architecture decisions,
and recovery evidence for the services hosted on Bumblebeam (`192.168.1.15`).

LAN names are split by role: real hosts use `host.home.arpa`; reverse-proxied
applications use `service.svc.home.arpa`. DHCP advertises `svc.home.arpa`, so bare
service names such as `http://hass/` remain convenient for LAN clients.

Runtime databases, plaintext secrets, certificates, logs, caches, downloads, Plex
metadata, and bulk media are intentionally excluded from Git. They belong in the
encrypted Restic backup or are explicitly classified as reproducible/bulk data.

Start with [the stabilisation runbook](docs/runbooks/stabilisation.md) and keep
[the task register](docs/task-register.md) current as checks are completed.
