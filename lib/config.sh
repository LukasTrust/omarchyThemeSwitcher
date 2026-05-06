#!/usr/bin/env bash
# Config helpers for omarchy-theme-switcher
# Stored at ~/.config/omarchy/theme-switcher.conf as KEY=VALUE pairs

SWITCHER_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/theme-switcher.conf"
SWITCHER_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/theme"
SWITCHER_LOG="$SWITCHER_STATE_DIR/switcher.log"

CONFIG_SCHEMA_VERSION=2

config_defaults() {
    cat <<'EOF'
CONFIG_VERSION=2
MODE=off
DAY_THEME=
NIGHT_THEME=
DAY_START=07:00
NIGHT_START=20:00
ROTATION_INTERVAL=daily
ROTATION_THEMES=
ROTATION_LAST_SWITCH=
ROTATION_LAST_THEME=
RANDOM_LOGIN_THEMES=
SAVED_THEME=
DAEMON_ACTIVE_PERIOD=
NOTIFY=false
PAUSED_UNTIL=
LAST_AUTO_THEME=
SCHEDULE_TYPE=clock
LATITUDE=
LONGITUDE=
TWILIGHT=civil
OVERRIDE_BEHAVIOR=respect
NEXT_EVENT_AT=
WIZARD_SHOWN=false
EOF
}

# Upgrade an existing config file to the current schema version by appending
# any missing keys with their default values, then stamping CONFIG_VERSION.
_config_upgrade() {
    local defaults_map
    declare -A defaults_map

    while IFS='=' read -r key val; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        defaults_map["$key"]="$val"
    done < <(config_defaults)

    local changed=false
    for key in "${!defaults_map[@]}"; do
        if ! grep -q "^${key}=" "$SWITCHER_CONF" 2>/dev/null; then
            echo "${key}=${defaults_map[$key]}" >> "$SWITCHER_CONF"
            changed=true
        fi
    done

    # Stamp or update the schema version
    if grep -q "^CONFIG_VERSION=" "$SWITCHER_CONF" 2>/dev/null; then
        config_set "CONFIG_VERSION" "$CONFIG_SCHEMA_VERSION"
    else
        echo "CONFIG_VERSION=$CONFIG_SCHEMA_VERSION" >> "$SWITCHER_CONF"
    fi
}

_CONFIG_INIT_RUNNING=false

config_init() {
    # Guard against re-entrant calls (config_set → config_init during upgrade)
    if $_CONFIG_INIT_RUNNING; then return; fi
    _CONFIG_INIT_RUNNING=true

    mkdir -p "$(dirname "$SWITCHER_CONF")"
    mkdir -p "$SWITCHER_STATE_DIR"
    if [[ ! -f "$SWITCHER_CONF" ]]; then
        config_defaults > "$SWITCHER_CONF"
        _CONFIG_INIT_RUNNING=false
        return
    fi

    local version
    version=$(grep -m1 "^CONFIG_VERSION=" "$SWITCHER_CONF" 2>/dev/null | cut -d= -f2-) || true
    if [[ -z "$version" || "$version" -lt "$CONFIG_SCHEMA_VERSION" ]]; then
        _config_upgrade
    fi
    _CONFIG_INIT_RUNNING=false
}

config_get() {
    local key="$1"
    local default="${2:-}"
    local val
    val=$(grep -m1 "^${key}=" "$SWITCHER_CONF" 2>/dev/null | cut -d= -f2-)
    echo "${val:-$default}"
}

# Atomic config_set: write via tmp+mv so partial writes never corrupt the file.
# Uses awk so values containing |, &, \, or = are handled safely.
config_set() {
    local key="$1"
    local value="$2"
    config_init
    local tmp="${SWITCHER_CONF}.tmp"
    if grep -q "^${key}=" "$SWITCHER_CONF" 2>/dev/null; then
        awk -v k="$key" -v v="$value" \
            '$0 ~ "^"k"="{print k"="v; next} {print}' \
            "$SWITCHER_CONF" > "$tmp" && mv "$tmp" "$SWITCHER_CONF"
    else
        echo "${key}=${value}" >> "$SWITCHER_CONF"
    fi
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

# Return sorted list of themes from ROTATION_THEMES or all installed themes
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

# ---------------------------------------------------------------------------
# Validators
# ---------------------------------------------------------------------------

# Returns 0 if the string is a valid HH:MM time (00:00–23:59)
validate_hhmm() {
    local t="$1"
    [[ "$t" =~ ^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$ ]]
}

# Returns 0 if lat/lon are plausible floating-point values in range
validate_latlon() {
    local lat="$1" lon="$2"
    [[ "$lat" =~ ^-?([0-8]?[0-9](\.[0-9]+)?|90(\.0+)?)$ ]] || return 1
    [[ "$lon" =~ ^-?(1?[0-7]?[0-9](\.[0-9]+)?|180(\.0+)?)$ ]] || return 1
}

# Returns 0 if the mode string is valid
validate_mode() {
    case "$1" in
        off|day-night|night-only|day-only|rotation|random-login) return 0 ;;
        *) return 1 ;;
    esac
}
