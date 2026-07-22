# ADR 0013: defer on-demand scale-to-zero (Sablier)

- Status: accepted
- Date: 2026-07-22

## Context

Adopting the orphaned `openspeedtest` container raised the idea of stopping
infrequently used services and starting them from a one-click portal control.
The portal is static nginx, so any "start on click" needs a standing privileged
actor; the established pattern is Sablier — a Traefik plugin plus a companion
container holding the Docker socket that starts a target container on first
request and stops it after idle.

Measured on 2026-07-22 before deciding:

- Host: 15.5 GiB RAM, **11 GiB available**, no swap pressure; every container
  idles at ≤ 1 % CPU.
- All plausible on-demand candidates combined — `structurizr-lite` (312 MiB),
  `seerr` (207), `app-shelf` (139), `video` (14), `openspeedtest` (15) — total
  **~0.7 GiB** idle, all LAN-only behind Traefik.

## Decision

**Do not deploy Sablier or any scale-to-zero machinery now.** Light,
infrequently used services stay running under their tracked Compose stacks.

- The memory it would reclaim is memory the host does not need; freed RAM would
  become page cache, not capability.
- The security trade inverts on this host: it would *add* a permanent,
  web-tier-reachable Docker-socket holder (the same authority class flagged on
  `docker-proxy`) to remove five sleepy LAN-only processes. Docker-socket
  authority is this host's real boundary (ADR 0004); we do not grow it to save
  megabytes.
- `structurizr-lite`, the heaviest infrequent service, is already scheduled for
  retirement — retirement reclaims its 312 MiB permanently and beats any
  on-demand scheme for it.

## Revisit conditions

Reopen this decision (and reach for Sablier, one deployment covering all
on-demand services at once) when **any** of the following occurs:

| Condition | Signal |
|---|---|
| A genuinely heavy idle service arrives | A service whose idle cost is measured in **GBs of RAM or GPU residency, not MBs** — e.g. a local **LLM runtime** (Ollama/LM Studio class, incl. ADR 0012 rung 4), a **game server**, or a **transcoder** kept hot |
| Host memory pressure | `available` RAM sustained below ~2 GiB, or any swapping under normal load |
| Fleet growth changes the sum | The combined idle cost of infrequently used services grows to a level that visibly competes with Plex/HA/media headroom |

When a trigger fires, the design intent is recorded here: Sablier as Traefik
middleware, the socket-holding component scoped as tightly as available tooling
allows, deployed once for the whole class of on-demand services — not
per-service one-offs.

## Consequences

- No new privileged surface; the portal stays a static page whose links *use*
  services rather than summon them.
- ~0.7 GiB of idle RAM remains spent on availability — accepted and measured.
- The decision is cheap to reverse: candidates are already isolated Compose
  stacks behind Traefik, which is exactly the shape Sablier consumes.
