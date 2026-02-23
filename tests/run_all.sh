#!/usr/bin/env bash
# Test runner for repo-understand
# Runs all test_*.sh files in the tests directory
# Reports pass/fail count, exits non-zero if any test fails

set -eo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"

# Source utilities for logging
. "$REPO_DIR/lib/util.sh"

PASS_COUNT=0
FAIL_COUNT=0
FAILED_TESTS=""

log_info "Running all tests..."
echo ""

for test_file in "$TESTS_DIR"/test_*.sh; do
    [ -f "$test_file" ] || continue

    test_name=$(basename "$test_file")
    printf "  %-40s " "$test_name"

    if bash "$test_file" > /dev/null 2>&1; then
        printf "PASS\n"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        printf "FAIL\n"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_TESTS="$FAILED_TESTS $test_name"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "Failed:$FAILED_TESTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 0
