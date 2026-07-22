# ADR 0014: Pomodoro DND terminology and Windows-agent extraction

- Status: accepted
- Date: 2026-07-22

## Context

ADR 0008 called the cube-driven routine "focus", but it does not start, track,
or complete Pomodoros and it does not drive Windows Focus mode. It mirrors the
cube's numbered/up-down orientation to Android and Windows **Do Not Disturb**.
The Windows client also runs on Ultra-Magners rather than Bumblebeam.

## Decision

- Current Home Assistant names use `pomodoro_dnd_*`; the canonical retained
  Windows topic is `pomodoro/dnd/state` with `on` / `off` payloads.
- `focus/state` remains dual-published only while installed legacy clients are
  migrated. It is removed after the new Windows DND agent is verified.
- The Windows code is extracted from this infrastructure repository to the
  separate `windows-dnd-agent` repository. Bumblebeam owns the HA, Zigbee, MQTT
  configuration and MQTT contract; the Windows repository owns the Windows
  client and installer.
- The physical cube/timer remains external to software. This integration only
  observes its orientation and controls DND; it makes no timer claim.

## Consequences

This correction keeps a working DND integration stable while making space for a
separate Pomodoro tracker. The future tracker must not infer completion from a
nominal face duration or treat DND as a source of timer state.
