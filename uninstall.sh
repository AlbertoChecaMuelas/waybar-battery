#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# uninstall.sh — revert waybar-battery deployment from ~/.config/waybar/
# ---------------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    echo "Do not run as root; this configures your user systemd instance and \$HOME." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 1. Flag parse
# ---------------------------------------------------------------------------
PURGE=0
if [[ "${1:-}" == "--purge" ]]; then
    PURGE=1
elif [[ -n "${1:-}" ]]; then
    echo "Usage: ./uninstall.sh [--purge]" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Remove deployed script
# ---------------------------------------------------------------------------
DEST="$HOME/.config/waybar/scripts/razer-battery.py"
if [ -n "$DEST" ] && [ -f "$DEST" ]; then
    rm "$DEST"
    echo "Removed: $DEST"
else
    echo "Deployed script not found, skipping: $DEST"
fi
rmdir --ignore-fail-on-non-empty "$HOME/.config/waybar/scripts" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Remove CSS block
# ---------------------------------------------------------------------------
STYLE="$HOME/.config/waybar/style.css"
if [[ -f "$STYLE" ]] && grep -qF '/* >>> waybar-battery >>> */' "$STYLE"; then
    if grep -qF '/* <<< waybar-battery <<< */' "$STYLE"; then
        sed -i '/>>> waybar-battery >>>/,/<<< waybar-battery <<</d' "$STYLE"
        echo "Removed waybar-battery CSS block from $STYLE."
    else
        echo "Warning: opening sentinel found but closing sentinel is missing in $STYLE." >&2
        echo "  Skipping automatic removal to avoid deleting unrelated CSS." >&2
        echo "  Please remove the waybar-battery block manually." >&2
    fi
else
    echo "No waybar-battery CSS block found in $STYLE, skipping."
fi

# ---------------------------------------------------------------------------
# 4. config.jsonc (no auto-edit — print instructions for manual removal)
# ---------------------------------------------------------------------------
echo ""
echo "Manual step required:"
echo "  Remove the following from ~/.config/waybar/config.jsonc:"
echo "    - The \"custom/mouse-battery\" module object"
echo "    - Its entry in the modules-right array"

# ---------------------------------------------------------------------------
# 5. Purge (packages, group, daemon) — only with --purge
# ---------------------------------------------------------------------------
if [[ $PURGE -eq 1 ]]; then
    echo ""
    echo "--- Purge mode active ---"

    # Disable and stop daemon
    systemctl --user disable --now openrazer-daemon || true

    # Remove user from group
    sudo gpasswd -d "$USER" openrazer || true

    # Remove packages via AUR helper if available
    HELPER=""
    for h in yay paru; do
        if command -v "$h" >/dev/null 2>&1; then
            HELPER="$h"
            break
        fi
    done

    if [[ -n "$HELPER" ]]; then
        "$HELPER" -Rns --noconfirm openrazer-driver-dkms openrazer-daemon python-openrazer || true
    else
        echo "Warning: no AUR helper (yay/paru) found. Packages were left in place." >&2
        echo "  To remove manually: sudo pacman -Rns openrazer-driver-dkms openrazer-daemon python-openrazer" >&2
    fi
else
    echo ""
    echo "Daemon, openrazer group and packages left untouched (use --purge to remove)."
fi

# ---------------------------------------------------------------------------
# 6. Reload Waybar (best-effort)
# ---------------------------------------------------------------------------
if pgrep -x waybar >/dev/null 2>&1; then
    echo "Reloading Waybar..."
    pkill -x waybar
    setsid waybar >/dev/null 2>&1 & disown || true
fi

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------
echo ""
echo "--- waybar-battery uninstall complete ---"
echo "Done:   razer-battery.py removed from ~/.config/waybar/scripts/"
echo "Done:   CSS block removed from style.css (or was already absent)"
echo "TODO:   Remove the custom/mouse-battery block from config.jsonc manually"
if [[ $PURGE -eq 0 ]]; then
    echo "INFO:   Daemon, openrazer group and packages are untouched (run with --purge to remove)"
fi
