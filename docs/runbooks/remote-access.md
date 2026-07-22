# Runbook: remote SSH access (Tailscale)

Decision and rationale: `docs/adr/0009-remote-ssh-access-via-tailscale.md`.

Bumblebeam runs Tailscale **natively** (systemd `tailscaled`, installed via apt) and
is reachable over the tailnet as `bumblebeam` / `100.85.155.36`. SSH itself is the
host's ordinary sshd; Tailscale only provides the network path.

## Connect from a device

1. Install the Tailscale client (App Store / Play Store / tailscale.com/download).
2. Sign in with the same account that owns the tailnet.
3. `ssh drdavient@bumblebeam` (MagicDNS) or `ssh drdavient@100.85.155.36`.
   Phones also need an SSH client app (e.g. Termius).

## Health checks

```bash
tailscale status          # peers and connection state (no sudo needed)
tailscale ip -4           # this host's tailnet IP
systemctl status tailscaled
tailscale ping <device>   # path check: direct vs DERP relay
```

## Re-authenticate (login expired / "logged out")

Node keys expire after ~180 days by default. Symptom: device shows as expired in
the admin console, or `tailscale status` reports logged out / NeedsLogin.

```bash
sudo tailscale up         # prints an auth URL; open it, sign in
```

Alternatively disable expiry for Bumblebeam in the admin console
(Machines → bumblebeam → Disable key expiry) — reasonable for an always-on server.

## Remote LAN and service access (subnet router + split DNS)

Since 2026-07-22 (ADR 0009 amendment) the tailnet provides the whole LAN, not
just SSH. Configuration lives in three places:

- **Host:** `sudo tailscale up --advertise-routes=192.168.1.0/24
  --advertise-exit-node` (flags are not cumulative — always re-run with the
  full set). Kernel forwarding: `/etc/sysctl.d/99-tailscale.conf` sets
  `net.ipv4.ip_forward=1` and `net.ipv6.conf.all.forwarding=1`.
- **Admin console approvals:** Machines → bumblebeam → route settings —
  approve `192.168.1.0/24` **and** tick "Use as exit node"; also "Disable key
  expiry" for bumblebeam (clients keep default expiry).
- **Admin console DNS:** split DNS nameserver `192.168.1.2` restricted to
  `home.arpa` (and `svc.home.arpa`, kept for clarity); search domain
  `svc.home.arpa` only — see the ADR amendment for why `home.arpa` must not be
  a search suffix. MagicDNS stays enabled; split DNS composes with it.

Client behaviour once set: `structurizr.svc.home.arpa` and bare `structurizr`
work anywhere; printers are added by LAN IP (mDNS discovery does not traverse
routed subnets); "Use exit node" stays **off** day-to-day — toggle it on
untrusted Wi-Fi only (throughput is bounded by home upload; if home is down
while enabled, the phone has no internet until toggled off).

Verify after any change:

```bash
tailscale status --json | grep -E 'PrimaryRoutes|ExitNodeOption' -A1
tailscale dns status      # split-DNS routes + search domains as served to nodes
```

`tailscale dns status` shows the *exact* strings the console serves — it caught
a typo'd split-DNS domain (`svc.home.arpas`) that silently matched nothing.

## Admin console

<https://login.tailscale.com/admin> — machines list, key expiry, MagicDNS
(Settings → DNS), device removal, route/exit-node approvals.

## Failure modes

- **Tailscale outage:** established tunnels keep working; adding/re-authing devices
  won't until it recovers. LAN SSH is unaffected.
- **`tailscaled` down:** `sudo systemctl restart tailscaled`. Independent of Docker —
  remote SSH survives Docker/Compose failures by design (see ADR 0009).
- **Traffic relayed (slow):** `tailscale ping bumblebeam` from the client; `via DERP`
  means NAT traversal failed — usually transient or a client-network firewall issue.

## Reinstall from scratch

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

State in `/var/lib/tailscale/` is reproducible by re-auth; it is not in Git or the
Restic set. The node reappears in the admin console on login (remove any stale old
entry there).
