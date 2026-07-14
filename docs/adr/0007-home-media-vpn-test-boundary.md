# ADR 0007: HOME_MEDIA VPN test boundary

- Status: accepted
- Date: 2026-07-14

## Decision

The HOME_MEDIA network is VPN-only for testing as well as normal application traffic.
This is an imperative, not a best-effort convention.

Every test that originates on, or sends traffic through, HOME_MEDIA must use Gluetun's
network namespace (`network_mode: container:gluetun`) and therefore traverse the active
VPN tunnel. This includes public-IP, DNS, tracker/indexer, metadata, download, import,
and other outbound connectivity tests. Run such probes with `docker exec gluetun …` or
from a purpose-built container that shares Gluetun's namespace.

Do not run these tests from the host, an agent sandbox, or a separate ordinary Docker
network. Do not temporarily detach a media service from Gluetun to make a test work.
If Gluetun is unhealthy, treat the required test as blocked and repair the tunnel first.

Ingress-only checks (for example, confirming that a LAN client or Traefik can load a
media UI) are distinct from an outbound HOME_MEDIA test. They must not initiate an
external media, tracker, DNS, or download request outside Gluetun.

## Consequences

- Test traffic cannot reveal the host's public IP or bypass the media kill-switch.
- A healthy Gluetun tunnel is a prerequisite for all HOME_MEDIA outbound verification.
- Recovery evidence must state that outbound media tests ran through Gluetun.
