#!/usr/bin/env python3
"""Pomodoro focus agent (Windows).

Subscribes to the MQTT `focus/state` topic that Home Assistant publishes from the
Aqara cube, and puts Windows into a focus state when a numbered face is up,
releasing it when the cube rests UP or face-down.

`focus/state` is a RETAINED topic, so the agent self-syncs to the current state
the moment it connects (including after a reboot).

    python focus_agent.py                 # normal run (reads config.ini beside this file)
    python focus_agent.py --test on        # apply focus once, no MQTT, then exit
    python focus_agent.py --test off
"""
import argparse
import configparser
import logging
import os
import subprocess
import sys

import paho.mqtt.client as mqtt

HERE = os.path.dirname(os.path.abspath(__file__))
log = logging.getLogger("focus-agent")


# --- Windows focus actuators -------------------------------------------------
def _set_toasts(enabled: bool):
    """Default, dependency-free, reliable: toggle Windows toast notifications."""
    import winreg

    key = r"Software\Microsoft\Windows\CurrentVersion\PushNotifications"
    with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, key, 0, winreg.KEY_SET_VALUE) as k:
        winreg.SetValueEx(k, "ToastEnabled", 0, winreg.REG_DWORD, 1 if enabled else 0)


def _set_focus_assist(level: int):
    """Experimental: toggle Focus Assist / Do-Not-Disturb via WNF.

    level: 0=Off, 1=Priority only, 2=Alarms only. This is undocumented and may be
    build-specific; if the DND moon icon does not change, switch method to
    `toasts` or `command` in config.ini.
    """
    import ctypes

    wnf = 0x0D83063EA3BE1075  # WNF_SHEL_QUIETHOURS_ACTIVE_PROFILE_CHANGED
    name = (ctypes.c_ulong * 2)(wnf & 0xFFFFFFFF, wnf >> 32)
    val = ctypes.c_int(level)
    status = ctypes.WinDLL("ntdll").NtUpdateWnfStateData(
        ctypes.byref(name), ctypes.byref(val), ctypes.sizeof(val), 0, 0, 0, 0
    )
    if status != 0:
        raise OSError(f"NtUpdateWnfStateData returned {status:#x}")


def apply_focus(on: bool, cfg):
    method = cfg.get("focus", "method", fallback="toasts").strip()
    log.info("focus %s (method=%s)", "ON" if on else "OFF", method)
    try:
        if method == "toasts":
            _set_toasts(enabled=not on)  # focus ON => toasts OFF
        elif method == "focus_assist":
            level = cfg.getint("focus", "assist_level", fallback=1)
            _set_focus_assist(level if on else 0)
        elif method == "command":
            cmd = cfg.get("focus", "on_command" if on else "off_command", fallback="").strip()
            if cmd:
                subprocess.run(cmd, shell=True, check=False)
        else:
            log.error("unknown focus method: %s", method)
    except Exception as e:  # never let an actuator error kill the agent
        log.error("failed to apply focus: %s", e)


# --- MQTT --------------------------------------------------------------------
def on_connect(client, userdata, flags, reason_code, properties=None):
    topic = userdata["cfg"].get("mqtt", "topic", fallback="focus/state")
    log.info("connected (%s); subscribing to %s", reason_code, topic)
    client.subscribe(topic)  # retained message is delivered here -> self-sync


def on_message(client, userdata, msg):
    payload = msg.payload.decode(errors="ignore").strip().lower()
    log.info("recv %s = %r", msg.topic, payload)
    if payload in ("on", "off"):
        apply_focus(payload == "on", userdata["cfg"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=os.path.join(HERE, "config.ini"))
    ap.add_argument("--test", choices=["on", "off"], help="apply focus once and exit")
    args = ap.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    cfg = configparser.ConfigParser()
    if not cfg.read(args.config):
        sys.exit(f"config not found: {args.config} (copy config.example.ini to config.ini)")

    if args.test:
        apply_focus(args.test == "on", cfg)
        return

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, userdata={"cfg": cfg})
    client.username_pw_set(cfg.get("mqtt", "username"), cfg.get("mqtt", "password"))
    client.on_connect = on_connect
    client.on_message = on_message
    host, port = cfg.get("mqtt", "host"), cfg.getint("mqtt", "port", fallback=1883)
    log.info("connecting to %s:%s", host, port)
    client.connect(host, port, keepalive=60)
    client.loop_forever(retry_first_connection=True)  # auto-reconnects forever


if __name__ == "__main__":
    main()
