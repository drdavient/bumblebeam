// Live service health for the Bumblebeam portal.
// Each service maps to a same-origin /health-api/<id> nginx proxy; any HTTP
// answer below 500 (or a redirect) counts as up, an nginx 502/504 or a
// timeout counts as down. Responses slower than SLOW_MS are flagged.

const SERVICES = [
  { id: "hass", name: "Home Assistant", group: "home" },
  { id: "plex", name: "Plex", group: "home" },
  { id: "n8n", name: "n8n", group: "home" },

  { id: "sonarr", name: "Sonarr", group: "media" },
  { id: "radarr", name: "Radarr", group: "media" },
  { id: "prowlarr", name: "Prowlarr", group: "media" },
  { id: "audiobookshelf", name: "Audiobookshelf", group: "media" },
  { id: "shelfarr", name: "Shelfarr", group: "media" },
  { id: "bookshelf", name: "Bookshelf", group: "media" },
  { id: "seerr", name: "Seerr", group: "media" },
  { id: "deluge", name: "Deluge", group: "media" },
  { id: "flaresolverr", name: "FlareSolverr", group: "media" },

  { id: "traefik", name: "Traefik", group: "platform" },
  { id: "syncthing", name: "Syncthing", group: "platform" },
  { id: "zigbee2mqtt", name: "Zigbee2MQTT", group: "platform" },
];

const TIMEOUT_MS = 6000;
const SLOW_MS = 2000;
const REFRESH_MS = 30000;

const STATES = {
  checking: { label: "Checking", glyph: "…" },
  up: { label: "Up", glyph: "●" },
  slow: { label: "Slow", glyph: "◐" },
  down: { label: "Down", glyph: "✕" },
};

function tileHtml(svc) {
  return `
    <article class="tile" id="tile-${svc.id}" data-state="checking">
      <span class="tile-glyph" aria-hidden="true">…</span>
      <span>
        <strong>${svc.name}</strong>
        <small class="tile-detail">waiting for first check</small>
      </span>
      <span class="tile-state">Checking</span>
    </article>`;
}

function render() {
  for (const group of ["home", "media", "platform"]) {
    document.getElementById(`group-${group}`).innerHTML = SERVICES
      .filter((s) => s.group === group)
      .map(tileHtml)
      .join("");
  }
}

function setTile(svc, state, detail) {
  const tile = document.getElementById(`tile-${svc.id}`);
  tile.dataset.state = state;
  tile.querySelector(".tile-glyph").textContent = STATES[state].glyph;
  tile.querySelector(".tile-state").textContent = STATES[state].label;
  tile.querySelector(".tile-detail").textContent = detail;
}

async function probe(svc) {
  const started = performance.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(`/health-api/${svc.id}`, {
      cache: "no-store",
      redirect: "manual",
      signal: controller.signal,
    });
    const ms = Math.round(performance.now() - started);
    const answered = res.type === "opaqueredirect" || res.status < 500;
    if (!answered) return setTile(svc, "down", `HTTP ${res.status}`), false;
    setTile(svc, ms > SLOW_MS ? "slow" : "up", `${ms} ms`);
    return true;
  } catch {
    setTile(svc, "down", "no response");
    return false;
  } finally {
    clearTimeout(timer);
  }
}

let lastChecked = null;

function updateSummary(upCount) {
  const summary = document.getElementById("summary");
  const total = SERVICES.length;
  const when = lastChecked
    ? `checked ${Math.max(0, Math.round((Date.now() - lastChecked) / 1000))}s ago`
    : "checking…";
  if (upCount === null) {
    summary.textContent = "Checking services…";
  } else if (upCount === total) {
    summary.textContent = `All ${total} services responding — ${when}.`;
  } else {
    summary.textContent = `${upCount} of ${total} services responding — ${when}.`;
  }
}

let sweeping = false;

async function sweep() {
  if (sweeping) return;
  sweeping = true;
  try {
    const results = await Promise.all(SERVICES.map(probe));
    lastChecked = Date.now();
    updateSummary(results.filter(Boolean).length);
  } finally {
    sweeping = false;
  }
}

render();
sweep();
setInterval(sweep, REFRESH_MS);
setInterval(() => {
  if (lastChecked) {
    const up = document.querySelectorAll('[data-state="up"], [data-state="slow"]').length;
    updateSummary(up);
  }
}, 5000);
document.getElementById("refresh").addEventListener("click", sweep);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) sweep();
});
