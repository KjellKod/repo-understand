#!/usr/bin/env bash
# Tests for lib/targeted/entry-points.sh
# Bash 3.2 compatible

set -eo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"

# Source dependencies
. "$REPO_DIR/lib/util.sh"
. "$REPO_DIR/lib/targeted/entry-points.sh"

PASS=0
FAIL=0
FIXTURE_DIR=""
TMP_DIR=""

_setup() {
    FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test-entrypoints-XXXXXX")
    FIXTURE_DIR=$(cd "$FIXTURE_DIR" && pwd)
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test-entrypoints-tmp-XXXXXX")
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

assert_line_count_range() {
    local file="$1"
    local min="$2"
    local max="$3"
    local msg="$4"
    local count
    count=$(wc -l < "$file" | tr -d ' ')
    if [ "$count" -ge "$min" ] && [ "$count" -le "$max" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $msg" >&2
        echo "  Expected between $min and $max lines, got $count" >&2
        cat "$file" >&2
    fi
}

# ─── Tests ────────────────────────────────────────────────────────────────────

test_keyword_matching() {
    _setup

    # Create a mini repo structure
    mkdir -p "$FIXTURE_DIR/src/comm"
    mkdir -p "$FIXTURE_DIR/src/billing"
    echo "// sms handler" > "$FIXTURE_DIR/src/comm/sms.js"
    echo "// email handler" > "$FIXTURE_DIR/src/comm/email.js"
    echo "// pricing" > "$FIXTURE_DIR/src/billing/pricing.js"
    echo "// unrelated" > "$FIXTURE_DIR/src/unrelated.js"

    detect_entry_points "Trace the SMS pipeline" "$FIXTURE_DIR" "$TMP_DIR"

    assert_file_contains "$TMP_DIR/entry_points.txt" "sms.js" \
        "Keyword matching: sms.js should be detected for 'SMS' query"

    assert_file_not_contains "$TMP_DIR/entry_points.txt" "unrelated.js" \
        "Keyword matching: unrelated.js should not be detected"

    _teardown
}

test_returns_2_to_5_results() {
    _setup

    # Create many matching files
    mkdir -p "$FIXTURE_DIR/src/sms"
    for i in 1 2 3 4 5 6 7 8; do
        echo "// file $i" > "$FIXTURE_DIR/src/sms/handler${i}.js"
    done
    echo "// sms main" > "$FIXTURE_DIR/src/sms/sms.js"

    detect_entry_points "Find the SMS handler" "$FIXTURE_DIR" "$TMP_DIR"

    local count
    count=$(wc -l < "$TMP_DIR/entry_points.txt" | tr -d ' ')

    if [ "$count" -ge 2 ] && [ "$count" -le 5 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: Expected 2-5 results, got $count" >&2
        cat "$TMP_DIR/entry_points.txt" >&2
    fi

    _teardown
}

test_no_match_fallback() {
    _setup

    # Create repo with index.js fallback
    echo "// main" > "$FIXTURE_DIR/index.js"
    echo "// other" > "$FIXTURE_DIR/other.js"

    detect_entry_points "xyzzy frobulate quux" "$FIXTURE_DIR" "$TMP_DIR"

    assert_file_contains "$TMP_DIR/entry_points.txt" "index.js" \
        "No-match fallback: should fall back to index.js"

    _teardown
}

test_package_json_fallback() {
    _setup

    # Create repo with package.json main
    mkdir -p "$FIXTURE_DIR/src"
    echo "// app entry" > "$FIXTURE_DIR/src/app.js"
    cat > "$FIXTURE_DIR/package.json" <<'EOF'
{
    "name": "test",
    "main": "src/app.js"
}
EOF

    detect_entry_points "xyzzy frobulate quux" "$FIXTURE_DIR" "$TMP_DIR"

    assert_file_contains "$TMP_DIR/entry_points.txt" "src/app.js" \
        "Package.json fallback: should use main field"

    _teardown
}

test_directory_name_matching() {
    _setup

    # Files in a directory matching the keyword
    mkdir -p "$FIXTURE_DIR/src/invoice"
    echo "// invoice handler" > "$FIXTURE_DIR/src/invoice/handler.js"
    echo "// invoice model" > "$FIXTURE_DIR/src/invoice/model.js"
    echo "// unrelated" > "$FIXTURE_DIR/src/other.js"

    detect_entry_points "Process the invoice" "$FIXTURE_DIR" "$TMP_DIR"

    assert_file_contains "$TMP_DIR/entry_points.txt" "invoice" \
        "Directory matching: files in 'invoice' directory should be detected"

    assert_file_not_contains "$TMP_DIR/entry_points.txt" "other.js" \
        "Directory matching: other.js should not be detected"

    _teardown
}

test_sparse_matches_still_return_minimum_two() {
    _setup

    # Exactly one direct keyword match plus one unrelated candidate
    mkdir -p "$FIXTURE_DIR/src"
    echo "// sms handler" > "$FIXTURE_DIR/src/sms.js"
    echo "// helper" > "$FIXTURE_DIR/src/helper.js"

    detect_entry_points "Trace the SMS flow" "$FIXTURE_DIR" "$TMP_DIR"

    assert_file_contains "$TMP_DIR/entry_points.txt" "sms.js" \
        "Sparse matches: direct keyword match should be included"
    assert_line_count_range "$TMP_DIR/entry_points.txt" 2 5 \
        "Sparse matches: should be supplemented to at least 2 entry points"

    _teardown
}

# ─── Run tests ────────────────────────────────────────────────────────────────

test_keyword_matching
test_returns_2_to_5_results
test_no_match_fallback
test_package_json_fallback
test_directory_name_matching
test_sparse_matches_still_return_minimum_two

echo ""
echo "test_entry_points.sh: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
