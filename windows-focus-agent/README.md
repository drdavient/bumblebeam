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

- **`dnd`** (default) — drives the real **Do not disturb** toggle: Win+N opens
  the Notification Center with focus on the toggle, Enter activates it, Esc
  closes the flyout. On Windows 11 2026 builds this is the *only* working
  lever: the live DND state exists solely in shell memory — the legacy toasts
  registry value is ignored, the old Focus Assist WNF state was removed, and
  the CloudStore registry blob is a lazily-flushed cache (confirmed
  empirically: registry dumps taken with DND off and on are byte-identical).
  UI Automation (`pywinauto`) reads the toggle state before activating, so a
  retained-message replay can never invert a manually-set DND state, and the
  result is verified afterwards. Needs an unlocked, interactive desktop
  session. If the toggle isn't found (non-English Windows renames the button),
  run `python focus_agent.py --dump-qs` and adjust the patterns in
  `_DND_FLYOUTS`.
- **`toasts`** / **`focus_assist`** — legacy levers for older Windows builds.
  Both are confirmed dead on 2026 builds; kept only in case the agent is reused
  on an older machine.
- **`command`** — runs your own `on_command` / `off_command` (e.g. a PowerShell
  or AutoHotkey script) on each transition. The most flexible escape hatch.

## Verifying Do Not Disturb

The moon icon can be ambiguous, so verify DND *functionally* with the included
toast script:

```powershell
powershell -ExecutionPolicy Bypass -File .\notify-test.ps1   # baseline: should pop up
python focus_agent.py --test on
powershell -ExecutionPolicy Bypass -File .\notify-test.ps1   # should be SUPPRESSED
python focus_agent.py --test off
powershell -ExecutionPolicy Bypass -File .\notify-test.ps1   # pops up again
```

## How it fits

```
Aqara cube -> Zigbee2MQTT -> Mosquitto (192.168.1.15:1883)
                                 ^
Home Assistant classifies face, debounces to the resting face, and publishes
retained focus/state on|off  ---->  this agent (read-only 'ultra-magners' MQTT user)
```

Nothing listens on the PC; the agent dials out to the broker and auto-reconnects.
See `docs/adr/0008-pomodoro-focus-routine.md` in the repo for the full design.
