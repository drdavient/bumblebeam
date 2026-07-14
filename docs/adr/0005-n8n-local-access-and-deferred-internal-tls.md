# ADR 0005: n8n local access and deferred internal TLS

- Status: accepted
- Date: 2026-07-14

## Decision

n8n keeps `N8N_SECURE_COOKIE=true` and remains HTTPS-only. The Bumblebeam service
portal links n8n to its public endpoint **`https://n8n.drdavient.com`** rather than the
local HTTP route. No trusted local TLS is introduced now; the durable fix is pre-scoped
and deferred behind an objective trigger (below).

## Problem

- n8n sets a `Secure` session cookie, and browsers refuse to send a `Secure` cookie over
  plain HTTP. So the existing local HTTP route (`n8n`, `n8n.svc.home.arpa` on Traefik's
  `web` entrypoint) serves the page but can never complete a login — you get n8n's
  "secure cookie" warning instead.
- `N8N_SECURE_COOKIE` is a single instance-wide flag; n8n cannot mark the cookie `Secure`
  for the HTTPS vhost and non-`Secure` for the HTTP vhost. Disabling it to make local
  HTTP work would also strip the `Secure` flag from the public HTTPS path — a security
  downgrade we decline.
- The internal namespaces cannot obtain publicly-trusted certificates: `.home.arpa` is
  reserved and non-delegable, and `.svc.home.arpa` is internal-only. So there is no
  trusted local TLS today — `https://n8n.svc.home.arpa/` would present Traefik's default
  certificate (browser warning) and then 404, because no local `websecure` router exists.

## Why defer

Local n8n use is currently light, and the public HTTPS endpoint is reachable and fully
functional from the LAN. The cost of the durable fix (internal TLS everywhere) is not yet
justified. Redirecting the portal to the public URL makes n8n usable now without any
security downgrade.

## Durable fix (pre-scoped, triggered)

"TLS everywhere, Flavour 2" — publicly-trusted certs for internal names via DNS-01 and
split-horizon DNS:

- Issue a publicly-trusted wildcard (e.g. `*.lan.drdavient.com`) using the **existing**
  Traefik Let's Encrypt resolver, which already runs `dnsChallenge` via Cloudflare
  (`traefik/traefik.yml`). No new provider setup; auto-renewal already in place.
- Serve that wildcard on `websecure` routers for internal services; split-horizon-resolve
  `*.lan.drdavient.com` to `192.168.1.15` on the GL.iNet DNS. No CA distribution — every
  device already trusts Let's Encrypt.
- Estimated ~1 day (size M). Carve-outs: **Plex** keeps its own TLS via `plex.direct`;
  **bare single-label names** (`http://hass/`) cannot be covered by a certificate and stay
  HTTP or move to FQDN access. This supersedes/extends ADR 0003's namespace model.
- When it lands, n8n keeps its `Secure` cookie and is reached locally at
  `https://n8n.lan.drdavient.com` (or equivalent); the portal link is repointed there.

**Trigger:** adopt the durable fix when local n8n use becomes heavy, or when another
service needs trusted local TLS. Until then this ADR holds.

## Consequences

- n8n is reached on the LAN via `https://n8n.drdavient.com` (portal link updated).
- That LAN path depends on the public certificate/domain and on `n8n.drdavient.com`
  resolving to Bumblebeam from the LAN (existing DNS or NAT hairpin); it is currently
  confirmed working.
- Cookie security is preserved on every path — no downgrade.
- n8n's local Traefik routers (`web` entrypoint) remain but are non-functional for login;
  they are left in place for when internal TLS lands rather than churned now.
