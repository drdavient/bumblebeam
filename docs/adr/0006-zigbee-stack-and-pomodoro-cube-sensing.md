# ADR 0006: Zigbee stack and Pomodoro-cube orientation sensing

- Status: accepted
- Date: 2026-07-14

## Decision

Introduce a local Zigbee stack on Bumblebeam — **Zigbee2MQTT + Mosquitto**, driving the
**SONOFF ZBDongle-E** (EFR32MG21, adapter `ember`) — to support local Zigbee sensors. The
first use is the **physical Pomodoro focus trigger**: an Aqara **DJT11LM** vibration
sensor attached to the user's existing cube timer, whose orientation is classified to
infer timer state and (a later phase) drive a Windows focus mode.

## Validation result (hardware capability — the gating question)

The DJT11LM paired and is fully supported (`lumi.vibration.aq1`), exposing raw
orientation telemetry: `angle_x/y/z`, `x_axis/y_axis/z_axis`, `action`, `strength`,
`vibration`, plus diagnostics. On 2026-07-14 all six cube faces were exercised and
confirmed:

| Face | Raw axis (x, y, z) | Dominant | Angle |
|---|---|---|---|
| Timer UP | (55, 25, −740) | −Z | `angle_z ≈ −85` |
| 25 | (1028, −7, 222) | +X | `angle_x ≈ +78` |
| 50 | (16, 1039, 237) | +Y | `angle_y ≈ +77` |
| 5 | (−930, 23, 228) | −X | `angle_x ≈ −76` |
| face down | (48, −4, 1227) | +Z | `angle_z ≈ +88` |
| 10 | (75, −1026, 244) | −Y | `angle_y ≈ −76` |

Findings: readings are **stable and repeatable** across taps (the reported DJT11LM
staleness did not manifest); faces separate by ~±1000 on the gravity axis vs ~tens
off-axis, giving **unambiguous, classifiable clusters**; both raw axis and computed angle
independently distinguish the faces. **Conclusion: full "which face is up" detection is
viable**, not merely a "timer moved" trigger. A dominant-axis rule (largest |value| + its
sign → one of ±X/±Y/±Z) classifies all six.

## Architecture

- New `zigbee/` Compose stack. `zigbee-net` is owned by this stack; `traefik-net` is
  consumed `external:`. Z2M frontend is Traefik-fronted at `z2m` / `z2m.svc.home.arpa`.
- Mosquitto listens on `127.0.0.1:1883` only (Home Assistant, host-networked, can reach
  it on loopback; Z2M reaches it over `zigbee-net`). It is **not** exposed to the LAN.
  Anonymous access is acceptable while unexposed, but **authentication must be added
  before the broker becomes a permanent Home Assistant dependency**.
- Z2M runtime state (`zigbee2mqtt/data/`: the generated `network_key`, `pan_id`,
  `database.db`, `coordinator_backup.json`) is Git-ignored — it is secret/runtime and
  belongs in the encrypted backup, not Git. Only `compose.yml`, `mosquitto.conf`, and
  `configuration.yaml.example` are tracked.

## Consequences

- A Zigbee coordinator and MQTT broker now run on Bumblebeam. Losing `zigbee2mqtt/data/`
  loses the Zigbee network identity (all devices must re-pair), so that directory must be
  added to the encrypted backup scope (`docs/inventory.md`).
- Deferred to later phases (not decided here): the **face → Pomodoro/focus-state
  mapping** (a product decision), the **Home Assistant MQTT wiring** (with broker auth),
  and the **Windows focus-state control mechanism**. Per the project handover, the Windows
  automation is explicitly the last phase.
