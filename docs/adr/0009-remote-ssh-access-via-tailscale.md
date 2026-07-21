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
  it out for host access.
