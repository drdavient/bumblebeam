# Windows focus agent

Puts Windows into a focus state when the Pomodoro cube is on a numbered face.
It subscribes to the retained MQTT topic `focus/state` (published by Home
Assistant on Bumblebeam) and applies a Windows action on `on` / `off`.

Because `focus/state` is retained, the agent **self-syncs** to the current state
whenever it starts or reconnects — no drift after a reboot.

## Setup (on the Windows PC)

1. Install Python 3 (from python.org or the Store), then:
   ```
   pip install -r requirements.txt
   ```
2. Copy `config.example.ini` to `config.ini` (host/user/topic are already correct
   for Bumblebeam). Store the **`ultra-magners`** password securely — see
   *Credentials* below, not in the file.
3. Test the Windows action without MQTT:
   ```
   python focus_agent.py --test on      # should silence notifications
   python focus_agent.py --test off     # should restore them
   ```
4. Run it:
   ```
   python focus_agent.py
   ```
   Flip the cube to a numbered face — the agent logs `focus ON` and applies it.

## Credentials

The password is never stored in `config.ini`. Provide it one of these ways (the
agent checks them in order):

1. **Environment variable** — set `MQTT_PASSWORD` (a user env var, or in the Task
   Scheduler action's environment).
2. **Windows Credential Manager** (recommended) — run once:
   ```
   python focus_agent.py --set-password
   ```
   It prompts and stores the password encrypted (DPAPI, tied to your Windows
   account) via `keyring`. Nothing touches disk in plaintext.
3. **Plaintext fallback** — a `password =` value in `config.ini` (discouraged).

## Autostart

Simplest: press `Win+R`, run `shell:startup`, and drop a shortcut to
`pythonw focus_agent.py` there (use `pythonw` so no console window appears).
For robustness, use Task Scheduler → "At log on" → run
`pythonw <path>\focus_agent.py`.

## Focus methods (`[focus] method =` in config.ini)

- **`toasts`** (default) — toggles Windows toast notifications via the registry.
  Dependency-free and reliable; suppresses notification popups while focused.
- **`focus_assist`** — experimental: toggles Focus Assist / Do-Not-Disturb (the
  moon icon) via an undocumented call. If the DND state doesn't visibly change on
  your Windows build, use `toasts` or `command` instead. `assist_level` sets the
  ON level (1 = Priority only, 2 = Alarms only).
- **`command`** — runs your own `on_command` / `off_command` (e.g. a PowerShell
  or AutoHotkey script) on each transition. The most flexible escape hatch.

## Verifying Do Not Disturb

The moon icon can be ambiguous, so verify DND *functionally* with the included
toast script:

```powershell
powershell -ExecutionPolicy Bypass -File .\notify-test.ps1   # baseline: should pop up
python focus_agent.py --test on                              # method=focus_assist
powershell -ExecutionPolicy Bypass -File .\notify-test.ps1   # should be SUPPRESSED
python focus_agent.py --test off
powershell -ExecutionPolicy Bypass -File .\notify-test.ps1   # pops up again
```

If the toast still pops up with `--test on`, the `focus_assist` call isn't taking
on this build — switch to `method = command` and drive DND another way.

## How it fits

```
Aqara cube -> Zigbee2MQTT -> Mosquitto (192.168.1.15:1883)
                                 ^
Home Assistant classifies face, debounces to the resting face, and publishes
retained focus/state on|off  ---->  this agent (read-only 'ultra-magners' MQTT user)
```

Nothing listens on the PC; the agent dials out to the broker and auto-reconnects.
See `docs/adr/0008-pomodoro-focus-routine.md` in the repo for the full design.
