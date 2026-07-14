# ADR 0008: Pomodoro focus routine

- Status: accepted
- Date: 2026-07-14

## Decision

A physical Aqara DJT11LM on the user's cube Pomodoro timer drives a focus state on
Windows and Android. The cube is the only control surface — the user flips it
manually; the software mirrors the current face and runs **no timers**.

Pipeline:

```
cube -> Zigbee2MQTT -> Mosquitto -> Home Assistant (classify + debounce)
                                       |-- Android: notify command_dnd
                                       '-- retained focus/state -> Windows agent
```

## Behaviour

- **Classification** (dominant gravity axis, validated in ADR 0006):
  `+X=25  -X=5  +Y=50  -Y=10  +Z=down  -Z=up`. A numbered face (5/10/25/50) means
  focus ON; UP or face-down means OFF.
- **Rest-only debounce.** A template binary sensor with 0.5 s `delay_on`/`delay_off`
  settles on the *resting* face, so numbered<->numbered flips (25<->5 work/rest)
  keep focus ON and transient mid-flip orientations are ignored.
- **Fan-out on change** (and on HA start, for self-sync): set Android
  Do-Not-Disturb via the Companion app (`command_dnd`, level from an adjustable
  `input_select`: priority_only / alarms_only / total_silence) and publish a
  **retained** `focus/state` (`on`/`off`).

## Components

- **HA package** `HomeAssistant/hadata/packages/pomodoro_focus.yaml` (MQTT sensor
  classifier, `input_select.focus_dnd_level`, `binary_sensor.focus_state`) plus the
  `pomodoro_focus_fanout` automation in `automations.yaml`.
- **Broker** (`zigbee/`): Mosquitto authenticated; a least-privilege `windows` user
  (ACL read-only on `focus/#`); LAN-exposed on `1883` for the Windows agent;
  persistence on so retained `focus/state` survives restarts.
- **Windows agent** (`windows-focus-agent/`): a paho-mqtt client that subscribes to
  `focus/state` and applies a Windows action. Methods: `toasts` (default, reliable
  notification suppression), `focus_assist` (experimental DND toggle), or `command`
  (run a user script). Outbound-only; auto-reconnects; self-syncs on the retained
  message.

## Status

- **Android path verified end-to-end** 2026-07-14: flipping between numbered and
  up faces drove `focus/state` off<->on tracking the cube, the phone DND followed,
  and the 0.5 s debounce held (no spurious toggles).
- Broker LAN exposure + ACL + persistence verified. Windows agent delivered;
  pending first on-device run.

## Consequences

- The MQTT broker is now reachable on the LAN. This is acceptable because it is
  authenticated, the `windows` user is ACL-limited to read-only non-sensitive data,
  and credentials live in Bitwarden (never in Git; `passwd` and the agent
  `config.ini` are ignored).
- Startup default is focus OFF (safe). The automation also clears DND on HA start.
- The Windows DND mechanism is the one part not testable from Bumblebeam, so the
  agent defaults to the reliable `toasts` method and offers a `command` escape
  hatch for per-build tuning.
- `zigbee/zigbee2mqtt/data/` (network key, coordinator backup) must be in the
  encrypted backup scope — see the task register.
