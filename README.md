# waybar-battery

Waybar scripts to show peripheral battery levels on Hyprland/Omarchy (CachyOS/Arch).

## Supported hardware

| Device | Status | Method |
|---|---|---|
| Razer Naga V2 Pro (Wireless) | Confirmed working | OpenRazer D-Bus |
| Other OpenRazer wireless mice with battery reporting | Should work | OpenRazer D-Bus |
| Keychron (via Keychron Link dongle, 3434:d030) | Not feasible | See Compatibility notes |

Other OpenRazer-supported wireless devices with battery reporting should work out of the box. Check the OpenRazer project for the full supported device list.

## Prerequisites

- Arch-based distro (CachyOS, Manjaro, etc.) or any distro with OpenRazer packages available
- [Waybar](https://github.com/Alexays/Waybar)
- A [Nerd Fonts](https://www.nerdfonts.com/) patched font configured in Waybar (required for the  mouse glyph to render)

## Installation

1. **Install required packages:**

   ```bash
   yay -S openrazer-driver-dkms openrazer-daemon python-openrazer
   ```

2. **Add your user to the `openrazer` group:**

   ```bash
   sudo gpasswd -a $USER openrazer
   ```

   The daemon checks group membership on startup and refuses to run if the user is not a member.

3. **Reboot** (group membership changes require a new login session):

   ```bash
   sudo reboot
   ```

4. **Deploy the script:**

   ```bash
   mkdir -p ~/.config/waybar/scripts
   cp razer-battery.py ~/.config/waybar/scripts/razer-battery.py
   chmod +x ~/.config/waybar/scripts/razer-battery.py
   ```

5. **Wire the Waybar config** — see the snippet below.

6. **Reload Waybar:**

   ```bash
   pkill waybar && waybar &
   ```

## Waybar config snippet

Add the module definition to your `~/.config/waybar/config.jsonc`:

```jsonc
"custom/mouse-battery": {
    "exec": "~/.config/waybar/scripts/razer-battery.py",
    "return-type": "json",
    "interval": 60,
    "tooltip": true
}
```

Then include `"custom/mouse-battery"` in your `modules-right` array:

```jsonc
"modules-right": [
    "custom/mouse-battery",
    // ... other modules
]
```

Add to your `~/.config/waybar/style.css` for status colours:

```css
#custom-mouse-battery {
    padding: 0 8px;
}

#custom-mouse-battery.warning {
    color: #e5a50a; /* amber at ≤20% */
}

#custom-mouse-battery.critical {
    color: #e53935; /* red at ≤10% */
    animation: blink 1s linear infinite;
}

#custom-mouse-battery.disconnected {
    opacity: 0.4;
}
```

## Troubleshooting

**Empty device list / script outputs `?`**

- Check daemon status: `systemctl --user status openrazer-daemon`
- Verify group membership: `groups` (must include `openrazer`)
- If groups are missing, re-run step 2 and reboot

**Daemon fails to start**

- The daemon exits at startup if the user is not in the `openrazer` group. Add the user and reboot.
- Check logs: `journalctl --user -u openrazer-daemon -n 50`

**Mouse icon () does not render**

- Your Waybar font must be a Nerd Fonts patched font. Set it in `~/.config/waybar/config.jsonc` under `"font"` or in your GTK theme.

## Compatibility notes

### Keychron Link dongle (3434:d030) — not feasible

The Keychron Link USB dongle is visible via `lsusb` but does not advertise standard HID battery usage pages. Neither `/sys/class/power_supply/`, upower, nor BlueZ enumerates it as a battery-capable device. Reading the battery level would require reverse-engineering a proprietary 32-byte raw HID protocol (Usage Page `0xFF60`), for which no public documentation exists. This path was investigated and abandoned.

### Why not upower / BlueZ for the Razer mouse?

The Naga V2 Pro uses a 2.4 GHz USB dongle, not Bluetooth. upower and BlueZ do not expose wireless-dongle battery levels for Razer hardware. OpenRazer is the only supported path.
