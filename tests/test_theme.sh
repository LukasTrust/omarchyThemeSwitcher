#!/usr/bin/env bash
# Tests for lib/theme.sh — apply_theme, random_theme, _notify, waybar restart
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/theme.sh"

config_init

# ── random_theme ───────────────────────────────────────────────────────────────

test_random_theme_from_pool() {
    config_set "RANDOM_LOGIN_THEMES" "alpine,frost,mocha"
    local t; t=$(random_theme)
    assert_true "random_theme not empty" test -n "$t"
    # Must be one of the pool members
    assert_true "random_theme in pool" echo "alpine frost mocha" | grep -qw "$t"
}

test_random_theme_from_all_when_pool_empty() {
    config_set "RANDOM_LOGIN_THEMES" ""
    # MOCK_THEME_LIST is set in _harness.sh; random_theme should return one of those
    local t; t=$(random_theme)
    assert_true "random_theme not empty (all themes)" test -n "$t"
}

test_random_theme_fails_gracefully_when_no_themes() {
    config_set "RANDOM_LOGIN_THEMES" ""
    # Override the mock to return nothing
    omarchy-theme-list() { return 0; }
    local rc=0
    random_theme 2>/dev/null || rc=$?
    assert_true "random_theme returns non-zero with empty pool" test "$rc" -ne 0
    # Restore mock
    omarchy-theme-list() { echo "$MOCK_THEME_LIST"; }
}

# ── apply_theme ─────────────────────────────────────────────────────────────────

test_apply_theme_calls_omarchy_theme_set() {
    LAST_SET_THEME=""
    apply_theme "frost" "test"
    assert_eq "apply_theme calls omarchy-theme-set" "frost" "$LAST_SET_THEME"
}

test_apply_theme_writes_log() {
    apply_theme "mocha" "test-reason"
    assert_true "apply writes log" grep -q "test-reason: applied mocha" "$SWITCHER_LOG"
}

test_apply_theme_auto_records_last_auto() {
    apply_theme "nord" "auto-test" --auto
    assert_eq "auto records LAST_AUTO_THEME" "nord" "$(config_get LAST_AUTO_THEME)"
}

test_apply_theme_no_auto_leaves_last_auto_unchanged() {
    config_set "LAST_AUTO_THEME" "previous"
    apply_theme "frost" "manual-test"
    assert_eq "non-auto does not update LAST_AUTO_THEME" "previous" "$(config_get LAST_AUTO_THEME)"
}

test_apply_theme_returns_nonzero_on_failure() {
    omarchy-theme-set() { return 1; }
    local rc=0
    apply_theme "bad-theme" "test" 2>/dev/null || rc=$?
    assert_true "failed apply returns non-zero" test "$rc" -ne 0
    # Restore mock
    omarchy-theme-set() { LAST_SET_THEME="$1"; return 0; }
}

# ── _notify ─────────────────────────────────────────────────────────────────────

test_notify_skipped_when_disabled() {
    config_set "NOTIFY" "false"
    NOTIFY_CALLED=0
    notify-send() { NOTIFY_CALLED=1; }
    _notify "frost"
    assert_eq "notify skipped when disabled" "0" "$NOTIFY_CALLED"
}

test_notify_called_when_enabled() {
    config_set "NOTIFY" "true"
    NOTIFY_CALLED=0
    notify-send() { NOTIFY_CALLED=1; return 0; }
    _notify "frost"
    assert_eq "notify called when enabled" "1" "$NOTIFY_CALLED"
    # Restore
    config_set "NOTIFY" "false"
    notify-send() { return 0; }
}

# ── Run ────────────────────────────────────────────────────────────────────────
test_random_theme_from_pool
test_random_theme_from_all_when_pool_empty
test_random_theme_fails_gracefully_when_no_themes
test_apply_theme_calls_omarchy_theme_set
test_apply_theme_writes_log
test_apply_theme_auto_records_last_auto
test_apply_theme_no_auto_leaves_last_auto_unchanged
test_apply_theme_returns_nonzero_on_failure
test_notify_skipped_when_disabled
test_notify_called_when_enabled

_report
