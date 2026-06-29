#!/usr/bin/env python3
"""Waybar exec script: query Razer Naga V2 Pro battery via OpenRazer D-Bus."""

import json
import os
import subprocess
import sys


NOTIFY_THRESHOLD = 10
STATE_FILE = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", "/run/user/{uid}".format(uid=os.getuid())),
    "razer-battery-state",
)


def _read_last_level():
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as fh:
            return int(fh.read().strip())
    except (OSError, ValueError):
        return None


def _write_last_level(level):
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(str(level))
        os.replace(tmp, STATE_FILE)
    except OSError:
        pass


def _clear_state():
    try:
        os.unlink(STATE_FILE)
    except OSError:
        pass


def _maybe_notify(name, level, charging):
    if charging or level > NOTIFY_THRESHOLD:
        _clear_state()
        return
    last = _read_last_level()
    if last is not None and level >= last:
        return
    subprocess.Popen(
        [
            "notify-send",
            "-u",
            "critical",
            "-i",
            "battery-caution",
            "-t",
            "10000",
            f"{name}: {level}%",
            f"Batería baja ({level}%)",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    _write_last_level(level)


def get_battery_info():
    try:
        from openrazer.client import DeviceManager

        dm = DeviceManager()
    except Exception as exc:
        return {"text": "", "tooltip": f"Mouse not connected ({exc})", "class": "disconnected"}

    for device in dm.devices:
        if not device.has("battery"):
            continue

        name = device.name
        level = device.battery_level
        charging = device.has("charging") and device.is_charging

        tooltip = f"{name}: {level}%"
        if charging:
            tooltip += " (charging)"

        if level <= 10:
            css_class = "critical"
        elif level <= 20:
            css_class = "warning"
        else:
            css_class = "normal"

        text = f"󰍽 {level}%"

        _maybe_notify(name, level, charging)

        return {"text": text, "tooltip": tooltip, "class": css_class}

    return {"text": "", "tooltip": "Mouse not connected", "class": "disconnected"}


if __name__ == "__main__":
    output = get_battery_info()
    print(json.dumps(output))
    sys.exit(0)