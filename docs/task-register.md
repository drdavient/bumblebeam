# Stabilisation task register

| Priority | Task | Status | Dependency / target | Acceptance test | Evidence |
|---|---|---|---|---|---|
| P0 | Review reported Plex token exposure | Deferred | Exposure is unverified; account-wide client reauthentication was declined | Revisit if evidence is substantiated; keep runtime token out of Git | Current checkout contains no Git history or exposed token evidence |
| P0 | Review previously embedded Cloudflare credentials | Deferred | Local embedding was corrected; external exposure is unverified | Keep scoped credentials out of Git; rotate during routine account maintenance if desired | Current checkout contains no Git history or exposed token evidence |
| P0 | Classify repository data | Done | Phase 0 | Inventory covers every service/state class | `docs/inventory.md` |
| P0 | Record baseline | Done | Phase 0 | Container, DNS, HTTP, mount, network, storage checks recorded | `docs/baseline-2026-07-11.md`; `docs/evidence/2026-07-11-implementation.md` |
| P0 | Verify Elements read-write mount | Done | Phase 0 | Expected UUID mounted `rw`; sentinel present | Host `findmnt` and successful repository write |
| P0 | Install Restic | Done | Phase 0 | `restic version` succeeds | Workspace-local Ubuntu 0.12.1 package |
| P0 | Initial consistent local snapshot | Done | Elements rw, Restic, recovery password | `restic check --read-data` and local restore pass | Latest `882bbdb4`; `docs/evidence/2026-07-11-implementation.md` |
| P0 | Temporary Dave-OneDrive copy | Done | Remote verification commands | Restic-aware copy, check, remote restore pass | Three snapshots copied; `restic check --read-data-subset=1/10` passed; representative remote restore passed 2026-07-11 |
| P0 | Exclude repository from Ultra-Magners sync | Blocked | Physical/remote client access | Repository absent from every desktop sync scope | Pending |
| P1 | Git boundary and examples | Done | Runtime credentials remain ignored; reported exposure is unverified | Ignore audit clean; Compose examples validate | Working tree changes |
| P1 | Standardise AI harness configuration | Done | Phase 1 | Canonical `.agents/AGENTS.md`; each harness reaches it via a shim; skills shared; harness/session state kept private; global `/onboard` + `/bootstrap` skills onboard new harnesses | `docs/adr/0002-agent-configuration-and-memory-standard.md`; `.agents/`; root `AGENTS.md`/`CLAUDE.md` shims; `~/.agents/skills/{onboard,bootstrap}` |
| P1 | Remove obsolete nested Git directories | Done | Obsolete attempts removed after backup evidence | Root Git sees only the intended repository boundary | `Home_Media/.git` and `ITS_Home_Media/` removed |
| P1 | Fix Cloudflare DDNS Compose | Done | Runtime credential rotation is deferred; local values remain ignored | `docker compose ... config --quiet` passes | Working tree changes |
| P1 | Add mount-safe backup automation | Done | Phase 1 | Read-only/missing/wrong Elements mount exits before repository creation | `docs/evidence/2026-07-11-implementation.md` |
| P1 | Pin shared Docker network identity | Done | Preserve current subnets while stabilising bridge names | Gluetun=`172.18.0.0/16` on `br-gluetun`; Traefik=`172.26.0.0/16` on `br-traefik`; host services=`172.22.0.0/24` on `br-host-svc` | `Home_Media/compose.yml`, `traefik/compose.yml`; host verification after recreation |
| P1 | Revive Bumblebeam service portal | Done | Git-managed static portal, no Elements dependency | `bumblebeam.home.arpa` returns 200; portal has no host port or Gluetun attachment | `portal/`; Traefik labels |
| P1 | Install one-shot Elements boot unit | Pending | Interactive sudo/root authority | Enabled unit runs once at boot without gating services; container exits 0 with restart policy `no` | Unit supplied under `mount-watcher/systemd/` |
| P1 | Canonical Traefik/Plex configuration | Done | Runtime deployment waits on backup; account credential changes remain deferred | Compose validates; canonical aliases and correct advertised IP render | `docs/evidence/2026-07-11-implementation.md` |
| P1 | Dedicated backup identity | Pending | After initial recovery safety | Two scheduled backups plus remote restore pass | Pending |
| P1 | Canonical DNS records and DHCP search domain | Blocked | LAN DNS/router access | All canonical names resolve to `192.168.1.15` | Pending |
| P1 | Home Assistant recovery | Partial | Proxy path restored; UI and automation test remain | UI + automation test pass | Direct and canonical proxy return 200 through `br-host-svc` |
| P1 | Plex recovery | Partial | Playback and ownership test; token rotation deferred | Ownership + playback pass | Direct and canonical proxy identity = 200 |
| P2 | n8n recovery | Partial | Recreate after security gate; webhook test | UI + webhook pass | Bare and compatibility proxy = 200; new canonical label not deployed |
| P2 | Gluetun/media recovery | Pending | Elements rw and network | Tunnel plus dependency tests pass | Pending |
| P2 | Daily timers and retention | Pending | Two manual verified backups | Timer succeeds; retention dry-run matches 7/4/12 | Pending |
| P2 | Monthly integrity/restore checks | Pending | Scheduled backup stable | Rotating subset and both restores pass | Pending |
| P3 | Append-only/object-lock or offline copy | Pending | Backend decision | Host deletion credentials cannot remove protected copy | Pending |
