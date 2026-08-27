# ADR 0017: on-LAN Windows clients must not accept the LAN subnet route

- Status: accepted
- Date: 2026-08-27

## Decision

Windows tailnet devices that live **on** the home LAN (currently `Ultra-Magners`,
`192.168.1.50`) run with subnet routes rejected:

```powershell
tailscale set --accept-routes=false
```

Everything else stays as ADR 0009 designed it: the `192.168.1.0/24` subnet route
remains advertised, split DNS (`home.arpa → 192.168.1.2`) remains configured
tailnet-wide, and "Use Tailscale DNS" remains enabled on the device.

## Problem

With Tailscale enabled on the Windows desktop, every `*.home.arpa` /
`*.svc.home.arpa` name stopped resolving — portal, all service links — while
public names (`n8n.drdavient.com`) kept working. Disabling Tailscale restored
everything; re-enabling it broke everything again, reproducibly.

Root cause is an interaction of three individually-correct pieces:

1. The tailnet advertises `192.168.1.0/24` as a subnet route (ADR 0009
   amendment) so off-LAN devices can reach the LAN.
2. **Windows Tailscale clients accept subnet routes automatically** — unlike
   Linux, which requires an explicit `--accept-routes`. The desktop therefore
   installed a tunnel route to the very LAN it already sits on.
3. With Tailscale DNS on, Windows NRPT rules send `home.arpa` queries to
   tailscaled's local proxy, which forwards them to `192.168.1.2` using its own
   routing — into the tunnel, hairpinning toward the GL.iNet's Tailscale
   interface, where dnsmasq's `local-service` (Local Service Only, deliberately
   set) refuses the non-LAN-sourced query. Every `.home.arpa` lookup fails at
   the OS resolver.

Bumblebeam itself is immune (Linux, routes not accepted), which is why all
server-side checks looked healthy throughout.

## Diagnostic signature

Worth keeping — this presentation is misleading to diagnose cold:

- All `*.home.arpa` names dead in browsers **and** `curl.exe`
  (`Could not resolve host`); public DNS names fine.
- `nslookup` **appears to work** — it queries the interface DNS server
  directly, bypassing NRPT, so it never exercises the broken path. (Its
  doubled-suffix answer, `name.svc.home.arpa.svc.home.arpa`, is a separate
  benign Windows nslookup quirk: search suffix is tried first and the
  `*.svc.home.arpa` wildcard answers it.)
- Toggling "Use Tailscale DNS settings" toggles the failure.
- `Get-DnsClientNrptPolicy` shows the `.home.arpa` namespace routed to
  `100.100.100.100`; `tailscale status --json` shows a peer advertising the
  device's own subnet in `PrimaryRoutes`.

## Consequences

- The desktop keeps full Tailscale (tailnet IPs, MagicDNS, Tailscale DNS) and
  reaches LAN services natively, as before.
- If the desktop ever roams off-LAN it must temporarily re-accept routes
  (`tailscale set --accept-routes=true`) to reach LAN addresses remotely —
  split DNS will resolve names, but without the route the `192.168.1.x`
  answers are unreachable. Acceptable: it is a desktop.
- Phones/laptops that genuinely roam keep accepting routes; for them the
  tunnel path is the point, and off-LAN the hairpin problem does not exist.
- Any future Windows device joining the tailnet while living on this LAN needs
  the same one-time setting.

## Observed drift from ADR 0009 (recorded, not changed here)

ADR 0009's amendment has Bumblebeam advertising `192.168.1.0/24`. As of today
**GL-MT3000 also advertises it and is the current primary** for the route
(`tailscale status --json`: PrimaryRoutes on the GL-MT3000 peer). Redundant
advertisement is legitimate failover, but it is undocumented; if it was not a
deliberate choice, review which node should be primary. This does not affect
the decision above — the Windows failure occurs regardless of which node
serves the route.

## Verification

- 2026-08-27: failure signature confirmed on `Ultra-Magners` (curl resolve
  failure with Tailscale DNS on; recovery with Tailscale off).
- `accept-routes=false` fix applied and pending confirmation on the device;
  update this line if the outcome differs.
