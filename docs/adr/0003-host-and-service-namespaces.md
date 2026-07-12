# ADR 0003: host and service namespaces

- Status: accepted
- Date: 2026-07-12

## Decision

Separate LAN names by role:

- Real devices use explicit `host.home.arpa` records: `bumblebeam`, `vodafone`,
  and `glinet`.
- Reverse-proxied applications use `service.svc.home.arpa`. The GL.iNet DNS server
  (`192.168.1.2`) serves a wildcard for this namespace to Bumblebeam
  (`192.168.1.15`).
- DHCP advertises `svc.home.arpa` as the search suffix, so bare application names
  such as `http://hass/` expand to `hass.svc.home.arpa`.

This supersedes ADR 0001's use of `service.home.arpa` for applications. Traefik
keeps bare and `*.svc.home.arpa` router rules. Existing `*.home.arpa` service
aliases may be removed only after deliberate compatibility review.

## Consequences

- Adding a normal reverse-proxied service needs no DNS edit.
- Mistyped service names reach Traefik and return its normal unknown-host response.
- The wildcard does not consume unknown host names under `home.arpa`.
- The Vodafone Hub (`192.168.1.1`) remains gateway/Wi-Fi; GL.iNet controls DHCP/DNS.
