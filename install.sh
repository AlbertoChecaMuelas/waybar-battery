#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# install.sh — deploy waybar-battery components to ~/.config/waybar/
# ---------------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    echo "Do not run as root; this configures your user systemd instance and \$HOME." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEEDS_RELOGIN=0

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------
HELPER=""
for h in yay paru; do
    if command -v "$h" >/dev/null 2>&1; then
        HELPER="$h"
        break
    fi
done

MISSING_PKGS=()
for pkg in openrazer-driver-dkms openrazer-daemon python-openrazer; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        echo "Package already installed: $pkg"
    elif [[ -n "$HELPER" ]]; then
        echo "Installing $pkg via $HELPER..."
        "$HELPER" -S --needed --noconfirm "$pkg" \
            || { echo "Warning: failed to install $pkg; continuing." >&2; }
    else
        MISSING_PKGS+=("$pkg")
    fi
done

if [[ -z "$HELPER" && ${#MISSING_PKGS[@]} -gt 0 ]]; then
    echo "Warning: no AUR helper (yay/paru) found. Please install the following packages manually:" >&2
    echo "  openrazer-driver-dkms  openrazer-daemon  python-openrazer" >&2
    echo "Then re-run this script." >&2
fi

# ---------------------------------------------------------------------------
# 2. Group
# ---------------------------------------------------------------------------
if id -nG "$USER" | grep -qw openrazer; then
    echo "User $USER is already in the openrazer group."
else
    echo "Adding $USER to the openrazer group..."
    sudo gpasswd -a "$USER" openrazer
    NEEDS_RELOGIN=1
fi

# ---------------------------------------------------------------------------
# 3. Daemon (best-effort, non-fatal)
# ---------------------------------------------------------------------------
systemctl --user enable --now openrazer-daemon \
    || echo "Warning: could not start openrazer-daemon yet (expected before relogin)." >&2

# ---------------------------------------------------------------------------
# 4. Disable OpenRazer's native battery notifier (the script owns notifications)
# ---------------------------------------------------------------------------
OPENRAZER_CONF="$HOME/.config/openrazer/razer.conf"
if [[ -f "$OPENRAZER_CONF" ]]; then
    if grep -qE '^[[:space:]]*battery_notifier[[:space:]]*=' "$OPENRAZER_CONF"; then
        sed -i 's/^[[:space:]]*battery_notifier[[:space:]]*=.*/battery_notifier = False/' "$OPENRAZER_CONF"
        echo "Disabled OpenRazer native battery notifier in $OPENRAZER_CONF"
    else
        printf '\nbattery_notifier = False\n' >> "$OPENRAZER_CONF"
        echo "Appended battery_notifier = False to $OPENRAZER_CONF"
    fi
fi

# ---------------------------------------------------------------------------
# 5. Deploy script
# ---------------------------------------------------------------------------
echo "Deploying razer-battery.py..."
mkdir -p "$HOME/.config/waybar/scripts"
install -m 0755 "$SCRIPT_DIR/razer-battery.py" "$HOME/.config/waybar/scripts/razer-battery.py"
echo "Deployed: $HOME/.config/waybar/scripts/razer-battery.py"

# ---------------------------------------------------------------------------
# 6. CSS wiring
# ---------------------------------------------------------------------------
STYLE="$HOME/.config/waybar/style.css"
mkdir -p "$(dirname "$STYLE")"
touch "$STYLE"

NEW_CSS_BLOCK=$(cat <<'CSSBLOCK'
/* >>> waybar-battery >>> */
#custom-mouse-battery {
    padding: 0 8px;
}

#custom-mouse-battery.warning {
    color: #e5a50a;
}

#custom-mouse-battery.critical {
    color: #e53935;
    animation: blink 1s linear infinite;
}

#custom-mouse-battery.charging {
    color: #43a047;
}

#custom-mouse-battery.disconnected {
    opacity: 0.4;
}
/* <<< waybar-battery <<< */
CSSBLOCK
)

if ! grep -qF '/* >>> waybar-battery >>> */' "$STYLE"; then
    printf '\n%s\n' "$NEW_CSS_BLOCK" >> "$STYLE"
    echo "CSS block appended to $STYLE"
elif grep -q '#custom-mouse-battery.charging' "$STYLE"; then
    echo "CSS .charging rule already present in $STYLE, skipping."
else
    BLOCK_FILE="$(mktemp)"
    printf '%s' "$NEW_CSS_BLOCK" > "$BLOCK_FILE"
    python3 - "$STYLE" "$BLOCK_FILE" <<'PYTHON'
import re, sys
style_file, block_file = sys.argv[1], sys.argv[2]
with open(style_file) as f:
    content = f.read()
with open(block_file) as f:
    new_block = f.read().rstrip("\n")
pattern = re.compile(
    r'/\* >>> waybar-battery >>> \*/.*?/\* <<< waybar-battery <<< \*/',
    re.DOTALL,
)
content = pattern.sub(new_block, content)
with open(style_file, 'w') as f:
    f.write(content)
PYTHON
    rm -f "$BLOCK_FILE"
    echo "Updated placeholder CSS block in $STYLE"
fi

# ---------------------------------------------------------------------------
# 7. config.jsonc (no auto-edit — print snippet for manual paste)
# ---------------------------------------------------------------------------
CONFIG="$HOME/.config/waybar/config.jsonc"
if [[ ! -f "$CONFIG" ]]; then
    echo "Warning: $CONFIG not found. Add the module manually." >&2
    echo "Add the following to your Waybar config:"
    cat <<'SNIPPET'

"custom/mouse-battery": {
    "exec": "~/.config/waybar/scripts/razer-battery.py",
    "return-type": "json",
    "interval": 60,
    "tooltip": true
},
SNIPPET
    echo "Also add \"custom/mouse-battery\" to your modules-right array."
elif ! grep -q 'custom/mouse-battery' "$CONFIG"; then
    echo ""
    echo "Add the following block to your Waybar config.jsonc:"
    cat <<'SNIPPET'

"custom/mouse-battery": {
    "exec": "~/.config/waybar/scripts/razer-battery.py",
    "return-type": "json",
    "interval": 60,
    "tooltip": true
},
SNIPPET
    echo "Also add \"custom/mouse-battery\" to your modules-right array."
else
    echo "config.jsonc already references the custom/mouse-battery module."
fi

# ---------------------------------------------------------------------------
# 8. Reload Waybar (or prompt for relogin)
# ---------------------------------------------------------------------------
if [[ $NEEDS_RELOGIN -eq 1 ]]; then
    echo ""
    echo "============================================================"
    echo "  REBOOT OR RE-LOGIN REQUIRED"
    echo "  The openrazer group change will take effect after a"
    echo "  relogin or reboot. Then reload Waybar manually."
    echo "============================================================"
else
    if pgrep -x waybar >/dev/null 2>&1; then
        echo "Reloading Waybar..."
        pkill -x waybar
        setsid waybar >/dev/null 2>&1 & disown || true
    fi
fi

# ---------------------------------------------------------------------------
# 9. Summary
# ---------------------------------------------------------------------------
echo ""
echo "--- waybar-battery install complete ---"
echo "Done:   razer-battery.py deployed to ~/.config/waybar/scripts/"
echo "Done:   CSS block appended to style.css (or already present)"
echo "Done:   OpenRazer native battery notifier disabled (script owns notifications)"
if [[ $NEEDS_RELOGIN -eq 1 ]]; then
    echo "TODO:   Re-login or reboot for the openrazer group to take effect"
fi
echo "TODO:   Paste the custom/mouse-battery snippet into config.jsonc (see above)"
