#!/usr/bin/env bash
# Shared test harness — sourced by each test_*.sh (do not run directly).
# Provides: assert_eq, assert_true, assert_false, pass/fail counters,
# a fresh isolated HOME per test suite, and mock omarchy commands.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LIB_DIR="$SCRIPT_DIR/../lib"

# ── Isolated filesystem ────────────────────────────────────────────────────────
TEST_HOME=$(mktemp -d)
_harness_cleanup() { rm -rf "$TEST_HOME"; }
trap _harness_cleanup EXIT

export HOME="$TEST_HOME"
export XDG_CONFIG_HOME="$TEST_HOME/.config"
export XDG_STATE_HOME="$TEST_HOME/.local/state"

# ── Mock omarchy commands ──────────────────────────────────────────────────────
# Tests override these as needed; defaults produce stable, harmless output.

MOCK_CURRENT_THEME="alpine"
MOCK_THEME_LIST="alpine
frost
mocha
nord
rose-pine"

omarchy-theme-set()     { LAST_SET_THEME="$1"; return 0; }
omarchy-theme-current() { echo "$MOCK_CURRENT_THEME"; }
omarchy-theme-list()    { echo "$MOCK_THEME_LIST"; }
notify-send()           { return 0; }
systemctl()             { return 0; }
systemd-run()           { return 0; }
pgrep()                 { return 1; }

export -f omarchy-theme-set omarchy-theme-current omarchy-theme-list
export -f notify-send systemctl systemd-run pgrep

# ── Assertion helpers ──────────────────────────────────────────────────────────
PASS=0
FAIL=0

_pass() { (( PASS++ )); }
_fail() {
    (( FAIL++ ))
    local desc="$1" expected="${2:-}" actual="${3:-}"
    if [[ -n "$expected" ]]; then
        printf 'FAIL  %s\n      expected: %s\n      got:      %s\n' "$desc" "$expected" "$actual"
    else
        printf 'FAIL  %s\n' "$desc"
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        _pass
    else
        _fail "$desc" "$expected" "$actual"
    fi
}

assert_ne() {
    local desc="$1" unexpected="$2" actual="$3"
    if [[ "$unexpected" != "$actual" ]]; then
        _pass
    else
        _fail "$desc" "(anything except '$unexpected')" "$actual"
    fi
}

assert_true() {
    local desc="$1"; shift
    if "$@" 2>/dev/null; then
        _pass
    else
        _fail "$desc"
    fi
}

assert_false() {
    local desc="$1"; shift
    if ! "$@" 2>/dev/null; then
        _pass
    else
        _fail "$desc"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        _pass
    else
        _fail "$desc" "*contains* '$needle'" "$haystack"
    fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [[ -f "$path" ]]; then _pass; else _fail "$desc" "file to exist" "$path"; fi
}

assert_dir_absent() {
    local desc="$1" path="$2"
    if [[ ! -d "$path" ]]; then _pass; else _fail "$desc" "dir to be absent" "$path"; fi
}

# ── Summary (call at end of each test file) ────────────────────────────────────
_report() {
    echo ""
    echo "$PASS passed, $FAIL failed"
    [[ $FAIL -eq 0 ]]
}
