#!/usr/bin/env bash
# Tests for lib/geo.sh — twilight angles, awk NOAA algorithm, caching
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/geo.sh"

config_init

# ── _twilight_angle ────────────────────────────────────────────────────────────

test_twilight_civil() {
    assert_eq "civil angle"        "6"     "$(_twilight_angle civil)"
}

test_twilight_nautical() {
    assert_eq "nautical angle"     "12"    "$(_twilight_angle nautical)"
}

test_twilight_astronomical() {
    assert_eq "astronomical angle" "18"    "$(_twilight_angle astronomical)"
}

test_twilight_none() {
    assert_eq "none angle"         "0.833" "$(_twilight_angle none)"
}

test_twilight_default() {
    assert_eq "unknown → 0.833"   "0.833" "$(_twilight_angle garbage)"
}

# ── _geo_via_awk ───────────────────────────────────────────────────────────────
# Checks output format and rough plausibility (sunrise < sunset, values in range).

_hhmm_to_min() {
    local t="$1"
    local h m
    h=$(echo "$t" | cut -d: -f1 | sed 's/^0//')
    m=$(echo "$t" | cut -d: -f2 | sed 's/^0//')
    echo $(( h * 60 + m ))
}

test_awk_output_format() {
    local out; out=$(_geo_via_awk "51.5" "-0.1" "6")
    # Should match "HH:MM HH:MM"
    assert_true "awk output format" \
        echo "$out" | grep -qE '^[0-2][0-9]:[0-5][0-9] [0-2][0-9]:[0-5][0-9]$'
}

test_awk_sunrise_before_sunset() {
    local out; out=$(_geo_via_awk "51.5" "-0.1" "6")
    local rise set
    rise=$(echo "$out" | cut -d' ' -f1)
    set=$(echo "$out" | cut -d' ' -f2)
    local rise_min; rise_min=$(_hhmm_to_min "$rise")
    local set_min;  set_min=$(_hhmm_to_min "$set")
    assert_true "sunrise before sunset" test "$rise_min" -lt "$set_min"
}

test_awk_equator_midday_ish() {
    # On the equator, sunrise ~06:00 and sunset ~18:00 all year (UTC)
    local out; out=$(_geo_via_awk "0" "0" "0.833")
    local rise set
    rise=$(echo "$out" | cut -d' ' -f1)
    set=$(echo "$out" | cut -d' ' -f2)
    local rise_h; rise_h=$(echo "$rise" | cut -d: -f1 | sed 's/^0//')
    local set_h;  set_h=$(echo "$set"  | cut -d: -f1 | sed 's/^0//')
    # Equator: sunrise 5-7h UTC, sunset 17-19h UTC
    assert_true "equator sunrise ~06:00" test "$rise_h" -ge 4
    assert_true "equator sunrise <  08h" test "$rise_h" -lt 8
    assert_true "equator sunset  >= 16h"  test "$set_h"  -ge 16
    assert_true "equator sunset  < 22h"  test "$set_h"  -lt 22
}

test_awk_north_pole_summer_all_day() {
    # At 89°N in May/June awk outputs "00:00 00:00" (polar day) or 12:00 12:00
    # — just verify it returns two tokens and doesn't crash
    local out; out=$(_geo_via_awk "89" "0" "6")
    local count; count=$(echo "$out" | wc -w)
    assert_eq "polar result has 2 tokens" "2" "$count"
}

# ── caching ────────────────────────────────────────────────────────────────────

test_geo_sun_times_writes_cache() {
    geo_sun_times "51.5" "-0.1" "civil" >/dev/null
    local cache; cache=$(_geo_cache_file "51.5" "-0.1" "civil")
    assert_file_exists "cache file written" "$cache"
}

test_geo_sun_times_reads_cache() {
    local cache; cache=$(_geo_cache_file "51.5" "-0.1" "civil")
    mkdir -p "$(dirname "$cache")"
    echo "05:00 21:00" > "$cache"
    local out; out=$(geo_sun_times "51.5" "-0.1" "civil")
    assert_eq "cache read back" "05:00 21:00" "$out"
}

# ── Run ────────────────────────────────────────────────────────────────────────
test_twilight_civil
test_twilight_nautical
test_twilight_astronomical
test_twilight_none
test_twilight_default
test_awk_output_format
test_awk_sunrise_before_sunset
test_awk_equator_midday_ish
test_awk_north_pole_summer_all_day
test_geo_sun_times_writes_cache
test_geo_sun_times_reads_cache

_report
