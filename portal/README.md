# Bumblebeam portal

Static nginx site on `traefik-net`, served at `http://bumblebeam` /
`http://bumblebeam.home.arpa` via Traefik. Two tabs:

- **Services** (`index.html`) — the launcher grid of links.
- **Health** (`health.html` + `health.js`) — live per-service status tiles.

## How the health dashboard works

The browser polls same-origin `/health-api/<service>` paths every 30 s (plus
on tab focus and the Refresh button). Each path is an nginx `proxy_pass`
(`nginx/default.conf`) to one **unauthenticated** health endpoint:

- Host-published ports (host-network services and Gluetun's published media
  ports) are probed at `192.168.1.15:<port>`.
- `traefik-net` neighbours (Seerr, Audiobookshelf, Zigbee2MQTT, n8n, Traefik)
  are probed by container DNS name; a variable + the Docker resolver keeps
  nginx alive when a container is absent.
- **Home Assistant is probed through Traefik** (`Host: hass.svc.home.arpa`):
  host port 8123 is firewalled to Traefik's static IP (`172.22.0.10`, matching
  HA `trusted_proxies`), so the browser path is the only — and most honest —
  probe path.

Status semantics in `health.js`: any HTTP answer `< 500` or a redirect = **Up**
(auth challenges like 401/302 prove the service answered); nginx 502/504 or a
6 s timeout = **Down**; an answer slower than 2 s = **Slow**. Colors are the
reserved status palette and never carry state alone — every tile pairs them
with a glyph and a text label.

## Adding a service

1. Add a `location = /health-api/<id>` proxy in `nginx/default.conf`
   (unauthenticated endpoint; container-name upstreams use the
   `set $var name; proxy_pass http://$var:port/...` pattern).
2. Add `{ id, name, group }` to `SERVICES` in `site/health.js`.
3. `docker compose config --quiet`, commit, `docker compose up -d`.

## Known gaps

- **VPN tunnel state is not shown.** Gluetun's control server is not
  listening on its published `:8888` (modern default is `:8000` and newer
  releases require an auth config); exposing `/v1/publicip/ip` needs a
  Gluetun config change and stack recreate. Until then, the arr/Deluge tiles
  prove Gluetun's ports are up but not that the tunnel has egress.
- Mosquitto (raw MQTT) has no HTTP endpoint and is not probed.
