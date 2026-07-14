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
- **Broker** (`zigbee/`): Mosquitto authenticated; a least-privilege `ultra-magners` user
  (ACL read-only on `focus/#`); LAN-exposed on `1883` for the Windows agent;
  persistence on so retained `focus/state` survives restarts.
- **Windows agent** (`windows-focus-agent/`): a paho-mqtt client that subscribes to
  `focus/state` and applies a Windows action. Default method `dnd` drives the real
  Quick Settings Do-Not-Disturb toggle via UI Automation (pywinauto); `toasts` and
  `focus_assist` are legacy levers for older builds; `command` runs a user script.
  Outbound-only; auto-reconnects; self-syncs on the retained message.

## Status

- **Android path verified end-to-end** 2026-07-14: flipping between numbered and
  up faces drove `focus/state` off<->on tracking the cube, the phone DND followed,
  and the 0.5 s debounce held (no spurious toggles).
- Broker LAN exposure + ACL + persistence verified. Windows agent delivered;
  pending first on-device run.
- **Windows DND lever reverse-engineered** 2026-07-14 on Ultra-Magners
  (Windows 11 2026 build): the legacy toasts registry value is ignored, the
  Focus Assist WNF state was removed (`STATUS_OBJECT_NAME_NOT_FOUND`), and
  registry dumps taken with DND off vs on are byte-identical — the CloudStore
  `quiethourssettings` blob is a lazily-flushed cache and the live state exists
  only in shell memory. No registry or documented API lever exists on this
  build, so the agent's default `dnd` method clicks the actual Quick Settings
  toggle via UI Automation (state-checked before and verified after each click).

## Consequences

- The MQTT broker is now reachable on the LAN. This is acceptable because it is
  authenticated, the `ultra-magners` user is ACL-limited to read-only non-sensitive data,
  and credentials live in Bitwarden (never in Git; `passwd` and the agent
  `config.ini` are ignored).
- Startup default is focus OFF (safe). The automation also clears DND on HA start.
- The Windows DND mechanism is not testable from Bumblebeam and Microsoft keeps
  no stable programmatic interface for it, so the default `dnd` method automates
  the UI itself — deliberately coupled to what the user sees rather than to
  undocumented internals that each build breaks. It needs an unlocked interactive
  session; `command` remains the escape hatch.
- `zigbee/zigbee2mqtt/data/` (network key, coordinator backup) must be in the
  encrypted backup scope — see the task register.
