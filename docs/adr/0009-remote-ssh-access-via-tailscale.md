# ADR 0009: Remote SSH access via Tailscale (native, not containerised)

- Status: accepted
- Date: 2026-07-15

## Decision

Remote SSH access to Bumblebeam is provided by **Tailscale installed natively on the
host** (apt package, `tailscaled` under systemd) — not by exposing sshd publicly, and
not by running Tailscale as a Compose service. Bumblebeam joins the personal tailnet
as `bumblebeam` (`100.85.155.36`); clients (laptop, phone) sign into the same tailnet
and reach the host's ordinary sshd over the tunnel. No public DNS record, router
port-forward, or Traefik change is made for SSH.

## Problem

The initial idea was to expose SSH at `bumblebeam.drdavient.com`, "like the n8n
setup". But the n8n pattern doesn't transfer:

- SSH is raw TCP, not HTTP. Traefik's Host-rule routing and Let's Encrypt certs
  don't apply; a plain SSH connection carries no hostname (no SNI), so
  hostname-based routing is impossible and the DNS name would only ever be a
  convenience label over a router port-forward.
- A forwarded port 22 exposes sshd to the entire internet — continuous brute-force
  and exploit scanning against the host's management lifeline, a much larger surface
  than n8n behind HTTPS + application login.

## Alternatives considered

- **Public port 22 + DDNS (the "n8n-alike"):** CNAME `bumblebeam` →
  `n8n.drdavient.com` (or second `cloudflare-ddns` instance) + router forward to
  `192.168.1.15:22`. Rejected: whole-internet exposure of sshd for zero functional
  gain over a tunnel.
- **Plain WireGuard (self-hosted):** same security model as Tailscale, fully
  self-hosted, but needs a router UDP port-forward, manual key/config management,
  and couples remote access to the DDNS record. Viable fallback if the Tailscale
  dependency (below) ever becomes unacceptable.
- **Tailscale in a container:** superficially matches the repo's Compose pattern,
  but to represent *the host* it needs `network_mode: host`, `/dev/net/tun`, and
  `NET_ADMIN` — a native daemon in a Docker costume, with none of the isolation that
  makes the container pattern valuable. Decisive objection: the times remote SSH
  matters most are when Docker itself is broken (wedged daemon, bad deploy, disk
  full, Docker upgrade); a containerised rescue line dies with the thing being
  rescued. A remote-access path must have strictly fewer dependencies than what it
  manages. Tailscale sits at the same layer as sshd, which is also (correctly) not
  in Compose.

## Consequences

- Remote SSH works from any signed-in device with no public exposure: nothing on
  Bumblebeam is reachable from the internet for this (Tailscale dials outbound and
  NAT-traverses; no port-forward exists to attack).
- New trust dependency: Tailscale's coordination service handles device auth and
  introductions (traffic itself is end-to-end encrypted WireGuard, direct
  device-to-device where possible). During a Tailscale outage existing connections
  persist but new devices can't be added. Headscale (self-hosted control server) or
  plain WireGuard are the exits if this trust ever needs revoking.
- Host state outside the repo, by design: the apt package, and
  `/var/lib/tailscale/` (node identity/keys). The state is reproducible by
  re-authenticating (`tailscale up`), so it is classified **reproducible** per
  `docs/inventory.md` — not committed, not required in the Restic set.
- sshd remains the authenticator (existing keys); Tailscale SSH (`tailscale up
  --ssh`, tailnet-identity auth) was deliberately not enabled. It can be adopted
  later without rework.
- Node keys expire by default (~180 days) and need a re-auth; see
  `docs/runbooks/remote-access.md`.
- Containerised Tailscale remains a legitimate future pattern for *service*-scoped
  needs (exit node, exposing a single service to the tailnet) — this ADR only rules
  it out for host access. *(Amended below: the exit node was subsequently enabled
  natively, superseding the containerised option for that need too.)*

## Amendment (2026-07-22): full remote LAN access — subnet router, split DNS, exit node

The scope grew from "remote SSH" to "the LAN from anywhere" when
`*.svc.home.arpa` services didn't resolve from a phone on the tailnet. Root
cause was never the services: LAN name resolution (ADR 0003 — GL.iNet
`192.168.1.2` serves the `*.svc.home.arpa` wildcard; DHCP advertises the search
suffix) simply doesn't exist off-LAN, and Bumblebeam advertised no route to LAN
addresses. Decisions, all host-native per this ADR's original rationale:

- **Subnet router:** Bumblebeam advertises `192.168.1.0/24` (approved in the
  admin console). The full LAN — not `/32`s — was a deliberate owner choice:
  single-user tailnet, and remote printing needs the printer. Kernel forwarding
  is now an explicit persistent host setting (`/etc/sysctl.d/99-tailscale.conf`:
  IPv4 + IPv6), no longer an accident of Docker's IPv4 default; IPv6 was
  included for imminent needs (exit node, Thread/Matter-class IPv6 devices).
- **Split DNS (admin console):** `home.arpa → 192.168.1.2` (covers subdomains,
  so it alone suffices; an explicit `svc.home.arpa` entry is kept as
  self-documentation). MagicDNS stays on — split DNS composes with it.
- **Search domain (admin console):** `svc.home.arpa` only — exact parity with
  ADR 0003's DHCP choice. `home.arpa` is deliberately *not* a search suffix:
  the `*.svc.home.arpa` wildcard answers every name, so an earlier suffix
  always shadows it; real hosts are typed fully qualified (`glinet.home.arpa`)
  or are tailnet machines (MagicDNS `bumblebeam`).
- **Exit node:** advertised and approved — an on-demand safe exit for untrusted
  Wi-Fi, off by default (throughput is bounded by home upload; if home is down
  while enabled the phone loses internet until toggled off). Enabled natively,
  superseding the "containerised for exit node" consequence above.
- **Key expiry disabled for Bumblebeam** (console): the node key now anchors
  routes, DNS, and exit — silent ~180-day expiry would kill remote access
  precisely when away, the catch-22 the rescue line exists to avoid. Client
  device keys still expire normally (re-auth is trivial in hand).

Verified 2026-07-22 from the phone on mobile data: fully-qualified and bare
service names resolve and load; `tailscale dns status` on the host is the
config-verification command (it caught a typo'd split-DNS domain,
`svc.home.arpas`, that silently matched nothing). Runbook:
`docs/runbooks/remote-access.md`.
