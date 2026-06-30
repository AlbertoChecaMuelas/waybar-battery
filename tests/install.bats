#!/usr/bin/env bats
# Tests for install.sh / uninstall.sh CSS logic and flag parsing.
# Requires: bats-core >= 1.5  (bats --version)
#
# What is covered:
#   1. CSS append idempotency      — running install.sh twice yields exactly one sentinel
#   2. CSS strip happy path        — block is removed; surrounding CSS survives
#   3. CSS strip missing-close guard — file untouched + warning printed when close sentinel absent
#   4. Flag parsing                — --purge exits 0; unknown flag exits 1
#   5. OpenRazer notifier flip     — step 4 forces battery_notifier = False, idempotent, safe on missing config
#   6. CSS auto-install            — step 6 appends/upgrades the styled block; idempotent across reruns and presets

REPO_ROOT="/home/espinilleitor/repos/own/waybar-battery"

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
    # Isolated HOME so no real config files are touched.
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"

    # Stub bin: all system commands that the scripts invoke get no-op stubs.
    STUB_BIN="$TEST_HOME/.stub-bin"
    mkdir -p "$STUB_BIN"

    # Commands that must simply succeed (exit 0, no output).
    for cmd in systemctl sudo pacman yay paru pkill setsid waybar; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/$cmd"
        chmod +x "$STUB_BIN/$cmd"
    done

    # pgrep exits 1 → "no waybar running" → reload block in both scripts is skipped.
    printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB_BIN/pgrep"
    chmod +x "$STUB_BIN/pgrep"

    export PATH="$STUB_BIN:$PATH"
}

teardown() {
    rm -rf "$TEST_HOME"
}

# ---------------------------------------------------------------------------
# 1. CSS append idempotency
# ---------------------------------------------------------------------------

@test "CSS append is idempotent: running install.sh twice does not duplicate the block" {
    run bash "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]

    run bash "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]

    STYLE="$HOME/.config/waybar/style.css"
    count="$(grep -c '>>> waybar-battery >>>' "$STYLE")"
    [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 2. CSS strip — happy path
# ---------------------------------------------------------------------------

@test "CSS strip happy path: block removed, surrounding CSS intact" {
    STYLE="$HOME/.config/waybar/style.css"
    mkdir -p "$(dirname "$STYLE")"

    # Write a style.css that wraps the sentinel block with real CSS on both sides.
    printf '%s\n' \
        'body { color: red; }' \
        '/* >>> waybar-battery >>> */' \
        '#custom-mouse-battery { /* style as needed */ }' \
        '/* <<< waybar-battery <<< */' \
        '.footer { display: flex; }' \
        > "$STYLE"

    run bash "$REPO_ROOT/uninstall.sh"
    [ "$status" -eq 0 ]

    # Sentinel lines must be gone.
    run grep -F '>>> waybar-battery >>>' "$STYLE"
    [ "$status" -ne 0 ]

    # CSS outside the sentinels must survive.
    run grep -F 'body { color: red; }' "$STYLE"
    [ "$status" -eq 0 ]

    run grep -F '.footer { display: flex; }' "$STYLE"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 3. CSS strip — missing closing sentinel guard
# ---------------------------------------------------------------------------

@test "CSS strip missing-close guard: file unchanged and warning printed" {
    STYLE="$HOME/.config/waybar/style.css"
    mkdir -p "$(dirname "$STYLE")"

    # Opening sentinel present, closing sentinel intentionally absent.
    # The line after the sentinel must NOT be deleted by the guard.
    printf '%s\n' \
        'body { color: red; }' \
        '/* >>> waybar-battery >>> */' \
        '.should-not-be-deleted { color: blue; }' \
        > "$STYLE"

    BEFORE_HASH="$(sha256sum "$STYLE" | awk '{print $1}')"

    # Merge stderr so the bats $output variable captures the warning.
    run bash "$REPO_ROOT/uninstall.sh" 2>&1
    [ "$status" -eq 0 ]

    # Warning about missing closing sentinel must appear.
    [[ "$output" == *"closing sentinel is missing"* ]]

    # File must be byte-for-byte identical to what it was before the run.
    AFTER_HASH="$(sha256sum "$STYLE" | awk '{print $1}')"
    [ "$BEFORE_HASH" = "$AFTER_HASH" ]
}

# ---------------------------------------------------------------------------
# 4. Flag parsing
# ---------------------------------------------------------------------------

@test "uninstall.sh flag parsing: --purge exits 0, unknown flag exits 1" {
    # Provide an empty style.css so uninstall does not error on missing file.
    STYLE="$HOME/.config/waybar/style.css"
    mkdir -p "$(dirname "$STYLE")"
    touch "$STYLE"

    run bash "$REPO_ROOT/uninstall.sh" --purge
    [ "$status" -eq 0 ]

    run bash "$REPO_ROOT/uninstall.sh" --foo
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 6. install.sh step 6 — CSS auto-install behaviour
# ---------------------------------------------------------------------------

@test "install.sh adds a fully styled CSS block on a fresh style.css" {
    run bash "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]

    STYLE="$HOME/.config/waybar/style.css"
    [ -f "$STYLE" ]

    run grep -F '#custom-mouse-battery.charging' "$STYLE"
    [ "$status" -eq 0 ]

    run grep -F '#custom-mouse-battery.warning' "$STYLE"
    [ "$status" -eq 0 ]

    run grep -F '#custom-mouse-battery.critical' "$STYLE"
    [ "$status" -eq 0 ]

    run grep -F '#custom-mouse-battery.disconnected' "$STYLE"
    [ "$status" -eq 0 ]
}

@test "install.sh upgrades an existing placeholder CSS block with full rules" {
    STYLE="$HOME/.config/waybar/style.css"
    mkdir -p "$(dirname "$STYLE")"
    printf '%s\n' \
        'body { color: red; }' \
        '/* >>> waybar-battery >>> */' \
        '#custom-mouse-battery {' \
        '    /* style as needed */' \
        '}' \
        '/* <<< waybar-battery <<< */' \
        '.footer { display: flex; }' \
        > "$STYLE"

    run bash "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]

    run grep -F '#custom-mouse-battery.charging' "$STYLE"
    [ "$status" -eq 0 ]

    run grep -F '/* style as needed */' "$STYLE"
    [ "$status" -ne 0 ]

    # Exactly one sentinel pair after upgrade.
    count="$(grep -c '>>> waybar-battery >>>' "$STYLE")"
    [ "$count" -eq 1 ]

    # Surrounding CSS preserved.
    run grep -F 'body { color: red; }' "$STYLE"
    [ "$status" -eq 0 ]
    run grep -F '.footer { display: flex; }' "$STYLE"
    [ "$status" -eq 0 ]
}

@test "install.sh leaves an already-styled CSS block untouched" {
    STYLE="$HOME/.config/waybar/style.css"
    mkdir -p "$(dirname "$STYLE")"
    printf '%s\n' \
        '/* >>> waybar-battery >>> */' \
        '#custom-mouse-battery.charging { color: #abcdef; }' \
        '/* <<< waybar-battery <<< */' \
        > "$STYLE"

    BEFORE_HASH="$(sha256sum "$STYLE" | awk '{print $1}')"

    run bash "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]

    AFTER_HASH="$(sha256sum "$STYLE" | awk '{print $1}')"
    [ "$BEFORE_HASH" = "$AFTER_HASH" ]
}

# ---------------------------------------------------------------------------
# 5. install.sh step 4 — OpenRazer battery_notifier management
# ---------------------------------------------------------------------------

@test "install.sh step 4: sets battery_notifier = False when key exists with True" {
    mkdir -p "$HOME/.config/openrazer"
    printf '%s\n' \
        '[Startup]' \
        'battery_notifier = True' \
        > "$HOME/.config/openrazer/razer.conf"

    run bash "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]

    run grep -E '^[[:space:]]*battery_notifier[[:space:]]*=' "$HOME/.config/openrazer/razer.conf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"battery_notifier = False"* ]]
}

@test "install.sh step 4: appends battery_notifier = False when key missing" {
    mkdir -p "$HOME/.config/openrazer"
    printf '%s\n' \
        '[Startup]' \
        'sync_effects_enabled = True' \
        > "$HOME/.config/openrazer/razer.conf"

    run bash "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]

    run grep -E '^[[:space:]]*battery_notifier[[:space:]]*=' "$HOME/.config/openrazer/razer.conf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"battery_notifier = False"* ]]
}

@test "install.sh step 4: skips cleanly when razer.conf does not exist" {
    run bash "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.config/openrazer/razer.conf" ]
}

@test "install.sh step 4: idempotent — running twice does not duplicate the line" {
    mkdir -p "$HOME/.config/openrazer"
    printf '%s\n' '[Startup]' 'battery_notifier = True' > "$HOME/.config/openrazer/razer.conf"

    run bash "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
    run bash "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]

    count=$(grep -cE '^[[:space:]]*battery_notifier[[:space:]]*=' "$HOME/.config/openrazer/razer.conf")
    [ "$count" -eq 1 ]
}
