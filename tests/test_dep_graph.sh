#!/usr/bin/env bash
# Tests for lib/targeted/dep-graph.sh
# Bash 3.2 compatible

set -eo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"

# Source dependencies
. "$REPO_DIR/lib/util.sh"
. "$REPO_DIR/lib/analyzers/imports.sh"
. "$REPO_DIR/lib/targeted/dep-graph.sh"

PASS=0
FAIL=0
FIXTURE_DIR=""
TMP_DIR=""

_setup() {
    FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test-depgraph-XXXXXX")
    FIXTURE_DIR=$(cd "$FIXTURE_DIR" && pwd)
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test-depgraph-tmp-XXXXXX")
    TMP_DIR=$(cd "$TMP_DIR" && pwd)
}

_teardown() {
    [ -n "$FIXTURE_DIR" ] && rm -rf "$FIXTURE_DIR"
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
}

trap _teardown EXIT

assert_file_contains() {
    local file="$1"
    local needle="$2"
    local msg="$3"
    if grep -qF "$needle" "$file" 2>/dev/null; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $msg" >&2
        echo "  Expected file to contain: $needle" >&2
        echo "  File contents:" >&2
        cat "$file" >&2
    fi
}

assert_file_not_contains() {
    local file="$1"
    local needle="$2"
    local msg="$3"
    if grep -qF "$needle" "$file" 2>/dev/null; then
        FAIL=$((FAIL + 1))
        echo "FAIL: $msg" >&2
        echo "  Expected file NOT to contain: $needle" >&2
    else
        PASS=$((PASS + 1))
    fi
}

assert_line_count() {
    local file="$1"
    local expected="$2"
    local msg="$3"
    local actual
    actual=$(wc -l < "$file" | tr -d ' ')
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $msg" >&2
        echo "  Expected $expected lines, got $actual" >&2
        echo "  File contents:" >&2
        cat "$file" >&2
    fi
}

# ─── Tests ────────────────────────────────────────────────────────────────────

test_depth_limit() {
    _setup

    # Create chain: A -> B -> C -> D
    cat > "$FIXTURE_DIR/a.js" <<EOF
const b = require('./b');
EOF
    cat > "$FIXTURE_DIR/b.js" <<EOF
const c = require('./c');
EOF
    cat > "$FIXTURE_DIR/c.js" <<EOF
const d = require('./d');
EOF
    cat > "$FIXTURE_DIR/d.js" <<EOF
// leaf node
EOF

    # Entry points file
    echo "$FIXTURE_DIR/a.js" > "$TMP_DIR/entry_points.txt"

    # Build with depth=2
    build_dep_graph "$TMP_DIR/entry_points.txt" "$FIXTURE_DIR" 2 "$TMP_DIR"

    assert_file_contains "$TMP_DIR/file_list.txt" "$FIXTURE_DIR/a.js" \
        "Depth limit: A should be in output (depth 0)"
    assert_file_contains "$TMP_DIR/file_list.txt" "$FIXTURE_DIR/b.js" \
        "Depth limit: B should be in output (depth 1)"
    assert_file_contains "$TMP_DIR/file_list.txt" "$FIXTURE_DIR/c.js" \
        "Depth limit: C should be in output (depth 2)"
    assert_file_not_contains "$TMP_DIR/file_list.txt" "$FIXTURE_DIR/d.js" \
        "Depth limit: D should NOT be in output (depth 3)"

    assert_line_count "$TMP_DIR/file_list.txt" 3 \
        "Depth limit: should have exactly 3 files"

    _teardown
}

test_cycle_detection() {
    _setup

    # Create cycle: A -> B -> A
    cat > "$FIXTURE_DIR/a.js" <<EOF
const b = require('./b');
EOF
    cat > "$FIXTURE_DIR/b.js" <<EOF
const a = require('./a');
EOF

    echo "$FIXTURE_DIR/a.js" > "$TMP_DIR/entry_points.txt"

    # Build with high depth to test cycle handling
    build_dep_graph "$TMP_DIR/entry_points.txt" "$FIXTURE_DIR" 10 "$TMP_DIR"

    assert_file_contains "$TMP_DIR/file_list.txt" "$FIXTURE_DIR/a.js" \
        "Cycle: A should be in output"
    assert_file_contains "$TMP_DIR/file_list.txt" "$FIXTURE_DIR/b.js" \
        "Cycle: B should be in output"

    assert_line_count "$TMP_DIR/file_list.txt" 2 \
        "Cycle: should have exactly 2 files (no duplicates)"

    _teardown
}

test_empty_entry_points() {
    _setup

    # Empty entry points file
    : > "$TMP_DIR/entry_points.txt"

    build_dep_graph "$TMP_DIR/entry_points.txt" "$FIXTURE_DIR" 2 "$TMP_DIR"

    local count
    count=$(wc -l < "$TMP_DIR/file_list.txt" | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: Empty entry points should produce empty output" >&2
    fi

    _teardown
}

test_missing_entry_point() {
    _setup

    echo "/nonexistent/file.js" > "$TMP_DIR/entry_points.txt"

    build_dep_graph "$TMP_DIR/entry_points.txt" "$FIXTURE_DIR" 2 "$TMP_DIR"

    local count
    count=$(wc -l < "$TMP_DIR/file_list.txt" | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: Missing entry point should produce empty output" >&2
    fi

    _teardown
}

test_multiple_entry_points() {
    _setup

    # Two separate trees
    cat > "$FIXTURE_DIR/x.js" <<EOF
const y = require('./y');
EOF
    echo "// leaf" > "$FIXTURE_DIR/y.js"
    echo "// standalone" > "$FIXTURE_DIR/z.js"

    # Two entry points
    echo "$FIXTURE_DIR/x.js" > "$TMP_DIR/entry_points.txt"
    echo "$FIXTURE_DIR/z.js" >> "$TMP_DIR/entry_points.txt"

    build_dep_graph "$TMP_DIR/entry_points.txt" "$FIXTURE_DIR" 2 "$TMP_DIR"

    assert_file_contains "$TMP_DIR/file_list.txt" "$FIXTURE_DIR/x.js" \
        "Multiple entries: x should be in output"
    assert_file_contains "$TMP_DIR/file_list.txt" "$FIXTURE_DIR/y.js" \
        "Multiple entries: y should be in output (dep of x)"
    assert_file_contains "$TMP_DIR/file_list.txt" "$FIXTURE_DIR/z.js" \
        "Multiple entries: z should be in output"

    assert_line_count "$TMP_DIR/file_list.txt" 3 \
        "Multiple entries: should have exactly 3 files"

    _teardown
}

# ─── Run tests ────────────────────────────────────────────────────────────────

test_depth_limit
test_cycle_detection
test_empty_entry_points
test_missing_entry_point
test_multiple_entry_points

echo ""
echo "test_dep_graph.sh: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
