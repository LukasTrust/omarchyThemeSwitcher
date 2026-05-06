#!/usr/bin/env bash
# Tests for lib/config.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
source "$LIB_DIR/config.sh"

# ── config_defaults ────────────────────────────────────────────────────────────

test_defaults_has_required_keys() {
    local out; out=$(config_defaults)
    for key in CONFIG_VERSION MODE DAY_THEME NIGHT_THEME DAY_START NIGHT_START \
                ROTATION_INTERVAL NOTIFY PAUSED_UNTIL LAST_AUTO_THEME \
                SCHEDULE_TYPE LATITUDE LONGITUDE TWILIGHT OVERRIDE_BEHAVIOR \
                WIZARD_SHOWN; do
        assert_true "defaults has $key" grep -q "^${key}=" <<< "$out"
    done
}

test_defaults_day_start_value() {
    assert_eq "DAY_START default" "07:00" "$(config_defaults | grep '^DAY_START=' | cut -d= -f2-)"
}

test_defaults_night_start_value() {
    assert_eq "NIGHT_START default" "20:00" "$(config_defaults | grep '^NIGHT_START=' | cut -d= -f2-)"
}

# ── config_init / config_get ───────────────────────────────────────────────────

test_init_creates_config_file() {
    config_init
    assert_file_exists "config file created" "$SWITCHER_CONF"
}

test_init_creates_state_dir() {
    config_init
    assert_true "state dir created" test -d "$SWITCHER_STATE_DIR"
}

test_get_value_from_file() {
    config_init
    config_get "DAY_START" | grep -q "." || true  # just verify it runs
    assert_eq "get DAY_START" "07:00" "$(config_get 'DAY_START')"
}

test_get_default_when_missing() {
    config_init
    assert_eq "get missing key with default" "fallback" "$(config_get 'NO_SUCH_KEY' 'fallback')"
}

test_get_empty_when_unset_no_default() {
    config_init
    assert_eq "get unset key no default" "" "$(config_get 'DAY_THEME')"
}

# ── config_set ─────────────────────────────────────────────────────────────────

test_set_existing_key() {
    config_init
    config_set "DAY_START" "08:30"
    assert_eq "set existing key" "08:30" "$(config_get 'DAY_START')"
}

test_set_new_key() {
    config_init
    config_set "MY_CUSTOM_KEY" "myvalue"
    assert_eq "set new key" "myvalue" "$(config_get 'MY_CUSTOM_KEY')"
}

test_set_value_with_equals() {
    config_init
    config_set "MODE" "day-night"
    assert_eq "set value with dash" "day-night" "$(config_get 'MODE')"
}

test_set_overwrites_previous() {
    config_init
    config_set "DAY_START" "06:00"
    config_set "DAY_START" "09:00"
    assert_eq "set overwrites" "09:00" "$(config_get 'DAY_START')"
}

test_set_empty_value() {
    config_init
    config_set "DAY_THEME" "frost"
    config_set "DAY_THEME" ""
    assert_eq "set empty value" "" "$(config_get 'DAY_THEME')"
}

# ── _config_upgrade ─────────────────────────────────────────────────────────────

test_upgrade_adds_missing_keys() {
    mkdir -p "$(dirname "$SWITCHER_CONF")"
    # Write a minimal old config without WIZARD_SHOWN
    printf 'CONFIG_VERSION=1\nMODE=off\n' > "$SWITCHER_CONF"
    _config_upgrade
    assert_true "upgrade adds WIZARD_SHOWN" grep -q "^WIZARD_SHOWN=" "$SWITCHER_CONF"
}

test_upgrade_does_not_overwrite_existing_values() {
    mkdir -p "$(dirname "$SWITCHER_CONF")"
    printf 'CONFIG_VERSION=1\nMODE=rotation\nDAY_START=09:00\n' > "$SWITCHER_CONF"
    _config_upgrade
    assert_eq "upgrade preserves MODE" "rotation" "$(config_get 'MODE')"
    assert_eq "upgrade preserves DAY_START" "09:00" "$(config_get 'DAY_START')"
}

# ── log_entry / log_trim ───────────────────────────────────────────────────────

test_log_entry_writes_message() {
    config_init
    log_entry "test message"
    assert_true "log file created" test -f "$SWITCHER_LOG"
    assert_true "log contains message" grep -q "test message" "$SWITCHER_LOG"
}

test_log_trim_keeps_max_lines() {
    config_init
    for i in $(seq 1 20); do echo "line $i" >> "$SWITCHER_LOG"; done
    log_trim 10
    local lines; lines=$(wc -l < "$SWITCHER_LOG")
    assert_eq "log trimmed to 10" "10" "$lines"
}

# ── config_purge ───────────────────────────────────────────────────────────────

test_purge_removes_config_and_state() {
    config_init
    log_entry "something"
    config_purge
    assert_true "config removed" test ! -f "$SWITCHER_CONF"
    assert_dir_absent "state dir removed" "$SWITCHER_STATE_DIR"
}

# ── theme_pool / random_login_pool ─────────────────────────────────────────────

test_theme_pool_uses_omarchy_list_when_empty() {
    config_init
    config_set "ROTATION_THEMES" ""
    local pool; pool=$(theme_pool)
    assert_contains "pool from omarchy-theme-list" "alpine" "$pool"
}

test_theme_pool_uses_config_when_set() {
    config_init
    config_set "ROTATION_THEMES" "frost,mocha"
    local pool; pool=$(theme_pool | tr '\n' ',')
    assert_contains "pool uses config" "frost" "$pool"
    assert_contains "pool uses config" "mocha" "$pool"
}

# ── Run ────────────────────────────────────────────────────────────────────────
test_defaults_has_required_keys
test_defaults_day_start_value
test_defaults_night_start_value
test_init_creates_config_file
test_init_creates_state_dir
test_get_value_from_file
test_get_default_when_missing
test_get_empty_when_unset_no_default
test_set_existing_key
test_set_new_key
test_set_value_with_equals
test_set_overwrites_previous
test_set_empty_value
test_upgrade_adds_missing_keys
test_upgrade_does_not_overwrite_existing_values
test_log_entry_writes_message
test_log_trim_keeps_max_lines
test_purge_removes_config_and_state
test_theme_pool_uses_omarchy_list_when_empty
test_theme_pool_uses_config_when_set

_report
