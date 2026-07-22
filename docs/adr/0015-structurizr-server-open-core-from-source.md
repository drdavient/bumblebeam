# ADR 0015: Structurizr Server — open core built from source

- Status: accepted
- Date: 2026-07-22

## Context

The register's three-stage plan (deploy Server → publish workspaces → retire
Lite) was written against `structurizr/onpremises` — free, authenticated,
multi-workspace. That product is archived. Its successor, **Structurizr
Server**, changed the ground:

- The prebuilt `structurizr/structurizr` image **license-gates `server` mode**
  (verified: clean exit 1 after "No license found"; licences start at
  £300/month — enterprise pricing, rejected for this host).
- The **open core is free but source-only** (Apache-2.0, single consolidated
  repo `structurizr/structurizr`), and omits: native authentication, the
  admin/workspace push API, S3/Azure storage.

Per-product Lite instances were rejected: the owner wants a C4 workspace for
**every shipped product**, and one JVM per product does not scale (and would
eventually trip ADR 0013's own scale-to-zero trigger).

## Decision

1. **Build open core from source.** `structurizr-server/Dockerfile` is a
   multi-stage build pinned to an upstream commit (`ARG STRUCTURIZR_REF`):
   Maven-builds the WAR, then mirrors upstream's own
   `Dockerfiles/eclipse-temurin-noble` runtime. The licence gate does not
   exist in the source (its strings appear nowhere in the repo). Compose
   carries the `build:` section — `docker compose build` is the whole
   pipeline; updating = bump the ref, rebuild, redeploy.
2. **Authentication via Traefik basicAuth**, since open core has none: a
   gitignored `traefik/users/structurizr.htpasswd` (APR1 hash, in the Restic
   set via the existing `traefik/` path) mounted into Traefik, applied by a
   middleware label on the `structurizr-server` router. Verified 401 without /
   200 with credentials. Exposure remains LAN + tailnet only.
3. **Publish by rendering, not API.** Open core has no admin/push API (its
   `regenerate-apikey` needs the licensed admin API; stored workspace keys are
   bcrypt-hashed). The supported substitute is file-based:
   `structurizr-server/publish.sh <id> <dsl>` renders versioned DSL to
   workspace JSON with the image's own `export` command and places it in
   `data/<id>/` — served immediately (`structurizr.cache=none`). Source DSL
   stays versioned in Git; server data stays runtime (gitignored, in Restic
   set and the consistent-backup stop list). Workspace *creation* is one
   `GET /workspace/create` behind basicAuth.

## Consequences

- Multi-workspace C4 publishing at zero licence cost; a new product's
  workspace is: create (one request) → `publish.sh <id> <dsl>`.
- We own a build: pinned-ref rebuilds are reproducible, but upstream changes
  (e.g. moving the licence gate into source) would surface at the next ref
  bump — re-evaluate then.
- The register's "publish through the Server API/CLI" note is superseded by
  `publish.sh` (the API it presumed is licensed-only); the "Server-native
  authentication" criterion is satisfied in substance by Traefik basicAuth.
- Lite retirement (stage 3) proceeds once the owner accepts both rendered
  workspaces; until then both run side by side (~600 MiB combined, within
  ADR 0013 headroom).
