# waybar-battery

Waybar scripts to show peripheral battery levels on Hyprland/Omarchy (CachyOS/Arch).

## Supported hardware

| Device | Status | Method |
|---|---|---|
| Razer Naga V2 Pro (Wireless) | Confirmed working | OpenRazer D-Bus |
| Other OpenRazer wireless mice with battery reporting | Should work | OpenRazer D-Bus |
| Keychron (via Keychron Link dongle, 3434:d030) | Not feasible | No channel available via 2.4 GHz dongle — see Compatibility notes |

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

The Keychron Link dongle (USB `3434:d030`) enumerates as four hidraw nodes:

- **hidraw0** — standard mouse HID
- **hidraw1** — Keychron proprietary protocol (Usage Page `0x8C`), with Report IDs `0xB1` (IN, 32 bytes), `0xB2` (OUT, 32 bytes), and `0x51`/`0x52`/`0x53`/`0x54` (FEATURE)
- **hidraw2** — standard QMK keyboard HID (carries keystrokes)
- **hidraw3** — QMK Raw HID interface (Usage Page `0xFF60`, Usage `0x61`), 32-byte reports, no Report ID

Both the QMK Raw HID interface (`hidraw3`) and the proprietary `0x8C` interface (`hidraw1`) accept writes from the host over USB, but the dongle does **not** retransmit those channels wirelessly to the keyboard. All reads timed out regardless of framing or command tried: 103 distinct command bytes were sent across three different framings with zero responses. During active keyboard use — confirmed by 255 HID reports on `hidraw2` — no reports appeared on `hidraw1` or `hidraw3`.

**Conclusion:** the dongle only retransmits standard HID keyboard and mouse reports wirelessly. Battery readout via the 2.4 GHz dongle is not possible through any known interface.

**Alternatives investigated and ruled out:**

- `upower`, `/sys/class/power_supply`, BlueZ: not viable — the dongle does not enumerate as a battery-capable device
- QMK Raw HID via USB cable: would only work when the keyboard is physically connected via USB, not in wireless mode

**Potential untested paths:**

- BLE GATT characteristic `0x2A19` (Battery Level): not tested because Bluetooth was occupied by another device at the time of investigation; may be viable if the keyboard pairs over BLE
- QMK Raw HID over USB cable (wired mode): functional for wired use, but not applicable in wireless mode

### Why not upower / BlueZ for the Razer mouse?

The Naga V2 Pro uses a 2.4 GHz USB dongle, not Bluetooth. upower and BlueZ do not expose wireless-dongle battery levels for Razer hardware. OpenRazer is the only supported path.
