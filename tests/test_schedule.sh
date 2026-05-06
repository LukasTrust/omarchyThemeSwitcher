#!/usr/bin/env bash
# Tests for lib/schedule.sh — time helpers, period detection, rotation logic
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/geo.sh"
source "$LIB_DIR/schedule.sh"

config_init

# ── time_to_minutes ────────────────────────────────────────────────────────────

test_ttm_midnight() {
    assert_eq "00:00 → 0"    "0"    "$(time_to_minutes '00:00')"
}

test_ttm_noon() {
    assert_eq "12:00 → 720"  "720"  "$(time_to_minutes '12:00')"
}

test_ttm_half_noon() {
    assert_eq "12:30 → 750"  "750"  "$(time_to_minutes '12:30')"
}

test_ttm_day_start() {
    assert_eq "07:00 → 420"  "420"  "$(time_to_minutes '07:00')"
}

test_ttm_night_start() {
    assert_eq "20:00 → 1200" "1200" "$(time_to_minutes '20:00')"
}

test_ttm_end_of_day() {
    assert_eq "23:59 → 1439" "1439" "$(time_to_minutes '23:59')"
}

# ── rotation_due ───────────────────────────────────────────────────────────────

test_rotation_due_first_run() {
    config_set "ROTATION_LAST_SWITCH" ""
    config_set "ROTATION_INTERVAL"    "daily"
    assert_true "due when never run" rotation_due
}

test_rotation_daily_same_day() {
    config_set "ROTATION_INTERVAL"    "daily"
    config_set "ROTATION_LAST_SWITCH" "$(date '+%Y-%m-%d')"
    assert_false "not due today (daily)" rotation_due
}

test_rotation_daily_yesterday() {
    config_set "ROTATION_INTERVAL"    "daily"
    config_set "ROTATION_LAST_SWITCH" "$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d')"
    assert_true "due after yesterday (daily)" rotation_due
}

test_rotation_monthly_same_month() {
    config_set "ROTATION_INTERVAL"    "monthly"
    config_set "ROTATION_LAST_SWITCH" "$(date '+%Y-%m')-01"
    assert_false "not due same month" rotation_due
}

# ── next_rotation_theme ─────────────────────────────────────────────────────────

test_rotation_first_theme_when_no_last() {
    config_set "ROTATION_THEMES"    "alpine,frost,mocha"
    config_set "ROTATION_LAST_THEME" ""
    local t; t=$(next_rotation_theme)
    assert_eq "first theme when no last" "alpine" "$t"
}

test_rotation_cycles_to_next() {
    config_set "ROTATION_THEMES"     "alpine,frost,mocha"
    config_set "ROTATION_LAST_THEME" "alpine"
    local t; t=$(next_rotation_theme)
    assert_eq "cycle: alpine → frost" "frost" "$t"
}

test_rotation_cycles_middle_to_last() {
    config_set "ROTATION_THEMES"     "alpine,frost,mocha"
    config_set "ROTATION_LAST_THEME" "frost"
    local t; t=$(next_rotation_theme)
    assert_eq "cycle: frost → mocha" "mocha" "$t"
}

test_rotation_wraps_around() {
    config_set "ROTATION_THEMES"     "alpine,frost,mocha"
    config_set "ROTATION_LAST_THEME" "mocha"
    local t; t=$(next_rotation_theme)
    assert_eq "wrap: mocha → alpine" "alpine" "$t"
}

test_rotation_fallback_when_last_not_in_pool() {
    config_set "ROTATION_THEMES"     "alpine,frost,mocha"
    config_set "ROTATION_LAST_THEME" "unknown-theme"
    local t; t=$(next_rotation_theme)
    assert_eq "fallback to first when last unknown" "alpine" "$t"
}

# ── current_period ──────────────────────────────────────────────────────────────
# We can't mock date easily, so we set boundaries that guarantee a known period
# regardless of the current clock time.

test_period_always_day_when_boundaries_wrap_whole_day() {
    # DAY_START=00:01, NIGHT_START=23:59 → it's always "day"
    config_set "SCHEDULE_TYPE" "clock"
    config_set "DAY_START"   "00:01"
    config_set "NIGHT_START" "23:59"
    assert_eq "wide day window → day" "day" "$(current_period)"
}

test_period_returns_valid_value() {
    config_set "SCHEDULE_TYPE" "clock"
    config_set "DAY_START"   "07:00"
    config_set "NIGHT_START" "20:00"
    local p; p=$(current_period)
    local valid=0
    [[ "$p" == "day" || "$p" == "night" ]] && valid=1
    assert_eq "current_period returns day or night" "1" "$valid"
}

# ── Run ────────────────────────────────────────────────────────────────────────
test_ttm_midnight
test_ttm_noon
test_ttm_half_noon
test_ttm_day_start
test_ttm_night_start
test_ttm_end_of_day
test_rotation_due_first_run
test_rotation_daily_same_day
test_rotation_daily_yesterday
test_rotation_monthly_same_month
test_rotation_first_theme_when_no_last
test_rotation_cycles_to_next
test_rotation_cycles_middle_to_last
test_rotation_wraps_around
test_rotation_fallback_when_last_not_in_pool
test_period_always_day_when_boundaries_wrap_whole_day
test_period_returns_valid_value

_report
