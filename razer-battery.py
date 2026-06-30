#!/usr/bin/env python3
"""Waybar exec script: query Razer Naga V2 Pro battery via OpenRazer D-Bus."""

import json
import os
import subprocess
import sys
import time


NOTIFY_THRESHOLD = 10
CHARGING_GRACE_SECONDS = 300
_RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", "/run/user/{uid}".format(uid=os.getuid()))
STATE_FILE = os.path.join(_RUNTIME_DIR, "razer-battery-state")
PREV_LEVEL_FILE = os.path.join(_RUNTIME_DIR, "razer-battery-prev-level")


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


def _read_prev_state():
    try:
        with open(PREV_LEVEL_FILE, "r", encoding="utf-8") as fh:
            content = fh.read().strip()
        try:
            data = json.loads(content)
            if isinstance(data, dict):
                return {
                    "prev": data.get("prev"),
                    "last_rise": float(data.get("last_rise", 0)),
                }
            return {"prev": int(data), "last_rise": 0}
        except (json.JSONDecodeError, ValueError, TypeError):
            return {"prev": int(content), "last_rise": 0}
    except (OSError, ValueError):
        return {"prev": None, "last_rise": 0}


def _write_prev_state(state):
    try:
        os.makedirs(os.path.dirname(PREV_LEVEL_FILE), exist_ok=True)
        tmp = PREV_LEVEL_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(state, fh)
        os.replace(tmp, PREV_LEVEL_FILE)
    except OSError:
        pass


def _detect_charging(level):
    """Heuristic for devices that don't expose charging state via OpenRazer.

    Returns True when the level has risen within the last
    CHARGING_GRACE_SECONDS seconds. A drop resets the grace window
    immediately, so unplugging is reflected without delay.
    """
    state = _read_prev_state()
    now = time.time()

    if state["prev"] is not None:
        if level > state["prev"]:
            state["last_rise"] = now
        elif level < state["prev"]:
            state["last_rise"] = 0

    state["prev"] = level
    last_rise = state["last_rise"]
    charging = last_rise > 0 and (now - last_rise) < CHARGING_GRACE_SECONDS

    _write_prev_state(state)
    return charging


def _maybe_notify(name, level, charging):
    if level <= 0:
        return
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
        if not charging:
            charging = _detect_charging(level)

        tooltip = f"{name}: {level}%"
        if charging:
            tooltip += " (charging)"

        if level <= 10:
            css_class = "critical"
        elif level <= 20:
            css_class = "warning"
        else:
            css_class = "normal"

        if charging:
            css_class = "charging"
            icon = "󰍽󰚥"
        else:
            icon = "󰍽"

        text = f"{icon} {level}%"

        _maybe_notify(name, level, charging)

        return {"text": text, "tooltip": tooltip, "class": css_class}

    return {"text": "", "tooltip": "Mouse not connected", "class": "disconnected"}


if __name__ == "__main__":
    output = get_battery_info()
    print(json.dumps(output))
    sys.exit(0)