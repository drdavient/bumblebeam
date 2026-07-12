# ADR 0001: canonical LAN namespace

- Status: accepted
- Date: 2026-07-11

## Decision

Use `service.home.arpa` as the canonical name for every LAN service and resolve it
to Bumblebeam at `192.168.1.15`. Advertise `home.arpa` as the DHCP search domain.
Retain `service.svc.home.arpa` as a temporary alias and bare `service` hostnames
for client convenience during migration.

`home.arpa` is reserved for residential networks and avoids relying on a public
DNS suffix for local-only routing. Traefik rules must list canonical, compatibility,
and bare names until the compatibility aliases are deliberately retired.

## Deferred decisions

Authelia, VLANs, DNS-platform migration, and broad hardening follow recovery of
Home Assistant, Plex, n8n, and the VPN/media stack.
