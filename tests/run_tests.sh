#!/usr/bin/env bash
# Run all test_*.sh files and report results.
# Usage: bash tests/run_tests.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

for suite in "$SCRIPT_DIR"/test_*.sh; do
    name="$(basename "$suite")"
    output=$(bash "$suite" 2>&1)
    status=$?

    # Extract pass/fail counts from last "N passed, N failed" line
    summary=$(echo "$output" | grep -E '^[0-9]+ passed' | tail -1)
    p=$(echo "$summary" | grep -oE '^[0-9]+')
    f=$(echo "$summary" | grep -oE '[0-9]+ failed' | grep -oE '^[0-9]+')
    TOTAL_PASS=$(( TOTAL_PASS + ${p:-0} ))
    TOTAL_FAIL=$(( TOTAL_FAIL + ${f:-0} ))

    if [[ $status -eq 0 ]]; then
        printf 'PASS  %s\n' "$name"
    else
        printf 'FAIL  %s\n' "$name"
        FAILED_SUITES+=("$name")
        # Print failures from suite output
        echo "$output" | grep -E '^(FAIL|ERR)' | sed 's/^/      /'
    fi
done

echo ""
echo "Total: $TOTAL_PASS passed, $TOTAL_FAIL failed"

if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
    echo ""
    echo "Failed suites:"
    for s in "${FAILED_SUITES[@]}"; do
        echo "  $s"
    done
    exit 1
fi
exit 0
