#!/usr/bin/env python3
"""Waybar exec script: query Razer Naga V2 Pro battery via OpenRazer D-Bus."""

import json
import sys


def get_battery_info():
    try:
        from openrazer.client import DeviceManager

        dm = DeviceManager()
    except Exception as exc:  # daemon not running, library absent, etc.
        return {"text": "", "tooltip": f"Mouse not connected ({exc})", "class": "disconnected"}

    for device in dm.devices:
        if not device.has("battery"):
            continue

        name = device.name
        level = device.battery_level

        tooltip = f"{name}: {level}%"
        if device.has("charging") and device.is_charging:
            tooltip += " (charging)"

        if level <= 10:
            css_class = "critical"
        elif level <= 20:
            css_class = "warning"
        else:
            css_class = "normal"

        # U+F5DF  nerd-font mouse icon; falls back gracefully in any font
        text = f" {level}%"

        return {"text": text, "tooltip": tooltip, "class": css_class}

    # No battery-capable device found
    return {"text": "", "tooltip": "Mouse not connected", "class": "disconnected"}


if __name__ == "__main__":
    output = get_battery_info()
    print(json.dumps(output))
    sys.exit(0)
