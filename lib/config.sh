#!/usr/bin/env bash
# Config helpers for omarchy-theme-switcher
# Stored at ~/.config/omarchy/theme-switcher.conf as KEY=VALUE pairs

SWITCHER_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/theme-switcher.conf"
SWITCHER_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/theme"
SWITCHER_LOG="$SWITCHER_STATE_DIR/switcher.log"

config_defaults() {
    echo "MODE=off"
    echo "DAY_THEME="
    echo "NIGHT_THEME="
    echo "DAY_START=07:00"
    echo "NIGHT_START=20:00"
    echo "ROTATION_INTERVAL=daily"
    echo "ROTATION_THEMES="
    echo "ROTATION_LAST_SWITCH="
    echo "ROTATION_LAST_THEME="
    echo "RANDOM_LOGIN_THEMES="
    echo "NOTIFY=false"
}

config_init() {
    mkdir -p "$(dirname "$SWITCHER_CONF")"
    mkdir -p "$SWITCHER_STATE_DIR"
    if [[ ! -f "$SWITCHER_CONF" ]]; then
        config_defaults > "$SWITCHER_CONF"
    fi
}

config_get() {
    local key="$1"
    local default="${2:-}"
    local val
    val=$(grep -m1 "^${key}=" "$SWITCHER_CONF" 2>/dev/null | cut -d= -f2-)
    echo "${val:-$default}"
}

config_set() {
    local key="$1"
    local value="$2"
    config_init
    if grep -q "^${key}=" "$SWITCHER_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$SWITCHER_CONF"
    else
        echo "${key}=${value}" >> "$SWITCHER_CONF"
    fi
}

config_load() {
    config_init
    # shellcheck source=/dev/null
    source "$SWITCHER_CONF"
}

log_entry() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$SWITCHER_LOG"
    log_trim 500
}

log_trim() {
    local max="${1:-500}"
    if [[ -f "$SWITCHER_LOG" ]]; then
        local lines
        lines=$(wc -l < "$SWITCHER_LOG")
        if (( lines > max )); then
            tail -n "$max" "$SWITCHER_LOG" > "${SWITCHER_LOG}.tmp" && mv "${SWITCHER_LOG}.tmp" "$SWITCHER_LOG"
        fi
    fi
}

config_purge() {
    local hook_file="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks/login"
    if [[ -f "$hook_file" ]] && grep -q "omarchy-theme-switcher" "$hook_file"; then
        rm -f "$hook_file"
    fi
    rm -f "$SWITCHER_CONF"
    rm -rf "$SWITCHER_STATE_DIR"
}

# Return sorted array of theme names from ROTATION_THEMES or all installed themes
theme_pool() {
    local pool
    pool=$(config_get "ROTATION_THEMES")
    if [[ -z "$pool" ]]; then
        omarchy-theme-list
    else
        tr ',' '\n' <<< "$pool" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort
    fi
}

random_login_pool() {
    local pool
    pool=$(config_get "RANDOM_LOGIN_THEMES")
    if [[ -z "$pool" ]]; then
        omarchy-theme-list
    else
        tr ',' '\n' <<< "$pool" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort
    fi
}
