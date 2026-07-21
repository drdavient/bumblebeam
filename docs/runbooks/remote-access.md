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

## Admin console

<https://login.tailscale.com/admin> — machines list, key expiry, MagicDNS
(Settings → DNS), device removal.

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
