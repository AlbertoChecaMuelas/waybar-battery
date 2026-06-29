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

Run the installer from the repository root:

```bash
./install.sh
```

**What `install.sh` does:**

- Installs `openrazer-driver-dkms`, `openrazer-daemon`, and `python-openrazer` via `yay` or `paru` (skipped if already installed; a warning is printed if no AUR helper is found).
- Adds your user to the `openrazer` group (if not already a member) and enables the `openrazer-daemon` systemd user service.
- Deploys `razer-battery.py` to `~/.config/waybar/scripts/`.
- Appends a **placeholder block** between sentinel markers to `~/.config/waybar/style.css` (idempotent — skipped if already present). The placeholder looks like:

  ```css
  /* >>> waybar-battery >>> */
  #custom-mouse-battery {
      /* style as needed */
  }
  /* <<< waybar-battery <<< */
  ```

  Paste the coloured styling rules inside that block manually (see [Waybar config snippet](#waybar-config-snippet)).
- **Prints** the `custom/mouse-battery` module snippet for you to paste into `config.jsonc` manually (the script does not auto-edit that file).
- Reloads Waybar if it is running (skipped when a re-login is required first).

**Manual step required after running `install.sh`:**

Paste the `custom/mouse-battery` snippet printed by the script into your `~/.config/waybar/config.jsonc` and add `"custom/mouse-battery"` to your `modules-right` array. See the [Waybar config snippet](#waybar-config-snippet) section below for the full block.

If you were newly added to the `openrazer` group, a **reboot or re-login** is required before the daemon and script will work correctly.

### Uninstalling

```bash
./uninstall.sh           # removes the deployed script and CSS block
./uninstall.sh --purge   # also disables the daemon, removes group membership, and uninstalls the packages
```

`uninstall.sh` does **not** auto-edit `config.jsonc`; remove the `custom/mouse-battery` block from that file manually.

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

Paste the following rules **inside** the placeholder block that `install.sh` added to `~/.config/waybar/style.css` (replace the `/* style as needed */` comment):

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
- If groups are missing, re-run `./install.sh` (or `sudo gpasswd -a $USER openrazer`) and reboot

**Daemon fails to start**

- The daemon exits at startup if the user is not in the `openrazer` group. Add the user and reboot.
- Check logs: `journalctl --user -u openrazer-daemon -n 50`

**Mouse icon () does not render**

- Your Waybar font must be a Nerd Fonts patched font. Set it in `~/.config/waybar/config.jsonc` under `"font"` or in your GTK theme.

**No AUR helper found (`yay` / `paru` not installed)**

- If neither `yay` nor `paru` is detected, `install.sh` prints a warning listing the three required packages (`openrazer-driver-dkms`, `openrazer-daemon`, `python-openrazer`) and continues without installing them. Install those packages manually before the mouse battery indicator will work.

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

## Development / Testing

Two test suites cover the project:

- `tests/install.bats` — install.sh / uninstall.sh wiring (CSS idempotency, sentinel handling, OpenRazer notifier flip, `--purge` flag parsing).
- `tests/test_razer_battery.py` — notification logic in `razer-battery.py` (threshold, charging reset, deduplication, state persistence).

**Prerequisites:**

```bash
sudo pacman -S bash-automated-testing-system python-pytest
```

**Run the suite:**

```bash
bats tests/install.bats
python3 -m pytest tests/test_razer_battery.py
```

**What they cover:**

- CSS block append idempotency (running `install.sh` twice does not duplicate the placeholder)
- CSS strip — happy path (sentinel markers present and removed cleanly by `uninstall.sh`)
- CSS strip — missing-close-sentinel guard (graceful behaviour when the closing sentinel is absent)
- `--purge` flag parsing
- install.sh step 4: forces `battery_notifier = False` in `~/.config/openrazer/razer.conf` (key present, key absent, no `razer.conf`, idempotent across reruns)
- `_maybe_notify()`: above-threshold suppression, charging reset, first-time-below notification, deduplication on equal or higher levels, re-notify on drops, threshold boundary at 10%
