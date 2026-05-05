#!/usr/bin/env bash
# theme.sh — central helpers for applying themes, notifications, and waybar

# Pick a random theme from the random-login pool
random_theme() {
    local pool
    mapfile -t pool < <(random_login_pool)
    if [[ ${#pool[@]} -eq 0 ]]; then
        echo ""
        return 1
    fi
    local idx=$(( RANDOM % ${#pool[@]} ))
    echo "${pool[$idx]}"
}

# Apply a theme, emit a log entry, send a notification, and revive waybar.
# Usage: apply_theme THEME REASON [--auto]
#   --auto  also records LAST_AUTO_THEME for override detection
# Returns non-zero if omarchy-theme-set fails.
apply_theme() {
    local theme="$1"
    local reason="$2"
    local auto=false
    [[ "${3:-}" == "--auto" ]] && auto=true

    if ! omarchy-theme-set "$theme" 2>/dev/null; then
        log_entry "ERROR: omarchy-theme-set \"$theme\" failed (reason: $reason)"
        return 1
    fi

    log_entry "$reason: applied $theme"

    if $auto; then
        config_set "LAST_AUTO_THEME" "$theme"
    fi

    _notify "$theme"
    _restart_waybar &
    disown 2>/dev/null || true
}

_notify() {
    local theme="$1"
    local enabled
    enabled=$(config_get "NOTIFY" "false")
    if [[ "$enabled" == "true" ]] && command -v notify-send &>/dev/null; then
        notify-send --app-name="Theme Switcher" "Theme changed" "Now using: $theme" 2>/dev/null || true
    fi
}

# Restart waybar after a theme switch.
# Prefers systemd supervision; falls back to polling + direct relaunch.
# Runs asynchronously (caller should background this).
_restart_waybar() {
    if systemctl --user is-enabled waybar.service &>/dev/null; then
        systemctl --user restart waybar 2>/dev/null || true
        return
    fi

    # Check if waybar was running before the theme switch; if not, nothing to do.
    if ! pgrep -x waybar >/dev/null 2>&1; then
        return
    fi

    # Poll until the old instance dies and restarts (omarchy-theme-set may have
    # triggered omarchy-restart-app), then revive it if it stays dead.
    local i
    for (( i=0; i<10; i++ )); do
        sleep 0.3
        pgrep -x waybar >/dev/null 2>&1 && return
    done

    log_entry "waybar not running after theme switch, relaunching"
    if command -v uwsm-app &>/dev/null; then
        setsid uwsm-app -- waybar >/dev/null 2>&1 &
    else
        setsid waybar >/dev/null 2>&1 &
    fi
}
