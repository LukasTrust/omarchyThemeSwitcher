#!/usr/bin/env bash
# Tests for the validator functions in lib/config.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
source "$LIB_DIR/config.sh"

# ── validate_hhmm ──────────────────────────────────────────────────────────────

test_hhmm_valid_zero() {
    assert_true  "00:00 valid"  validate_hhmm "00:00"
}

test_hhmm_valid_noon() {
    assert_true  "12:00 valid"  validate_hhmm "12:00"
}

test_hhmm_valid_end_of_day() {
    assert_true  "23:59 valid"  validate_hhmm "23:59"
}

test_hhmm_valid_single_digit_hour() {
    assert_true  "7:30 valid"   validate_hhmm "7:30"
}

test_hhmm_valid_leading_zero() {
    assert_true  "07:05 valid"  validate_hhmm "07:05"
}

test_hhmm_invalid_hour_24() {
    assert_false "24:00 invalid" validate_hhmm "24:00"
}

test_hhmm_invalid_minute_60() {
    assert_false "07:60 invalid" validate_hhmm "07:60"
}

test_hhmm_invalid_alpha() {
    assert_false "abc invalid"   validate_hhmm "abc"
}

test_hhmm_invalid_missing_colon() {
    assert_false "0700 invalid"  validate_hhmm "0700"
}

test_hhmm_invalid_empty() {
    assert_false "empty invalid" validate_hhmm ""
}

# ── validate_latlon ────────────────────────────────────────────────────────────

test_latlon_valid_london() {
    assert_true  "London valid"       validate_latlon "51.5"  "-0.1"
}

test_latlon_valid_poles() {
    assert_true  "north pole valid"   validate_latlon "90"    "0"
    assert_true  "south pole valid"   validate_latlon "-90"   "0"
}

test_latlon_valid_date_line() {
    assert_true  "+180 lon valid"     validate_latlon "0"     "180"
    assert_true  "-180 lon valid"     validate_latlon "0"     "-180"
}

test_latlon_valid_zero_zero() {
    assert_true  "0,0 valid"          validate_latlon "0"     "0"
}

test_latlon_invalid_lat_too_high() {
    assert_false "lat 91 invalid"     validate_latlon "91"    "0"
}

test_latlon_invalid_lon_too_high() {
    assert_false "lon 181 invalid"    validate_latlon "0"     "181"
}

test_latlon_invalid_alpha() {
    assert_false "alpha lat invalid"  validate_latlon "abc"   "0"
}

# ── validate_mode ──────────────────────────────────────────────────────────────

test_mode_off() {
    assert_true  "off valid"          validate_mode "off"
}

test_mode_day_night() {
    assert_true  "day-night valid"    validate_mode "day-night"
}

test_mode_night_only() {
    assert_true  "night-only valid"   validate_mode "night-only"
}

test_mode_day_only() {
    assert_true  "day-only valid"     validate_mode "day-only"
}

test_mode_rotation() {
    assert_true  "rotation valid"     validate_mode "rotation"
}

test_mode_random_login() {
    assert_true  "random-login valid" validate_mode "random-login"
}

test_mode_invalid() {
    assert_false "unknown invalid"    validate_mode "unknown"
    assert_false "empty invalid"      validate_mode ""
    assert_false "DAY-NIGHT invalid"  validate_mode "DAY-NIGHT"
}

# ── Run ────────────────────────────────────────────────────────────────────────
test_hhmm_valid_zero
test_hhmm_valid_noon
test_hhmm_valid_end_of_day
test_hhmm_valid_single_digit_hour
test_hhmm_valid_leading_zero
test_hhmm_invalid_hour_24
test_hhmm_invalid_minute_60
test_hhmm_invalid_alpha
test_hhmm_invalid_missing_colon
test_hhmm_invalid_empty
test_latlon_valid_london
test_latlon_valid_poles
test_latlon_valid_date_line
test_latlon_valid_zero_zero
test_latlon_invalid_lat_too_high
test_latlon_invalid_lon_too_high
test_latlon_invalid_alpha
test_mode_off
test_mode_day_night
test_mode_night_only
test_mode_day_only
test_mode_rotation
test_mode_random_login
test_mode_invalid

_report
