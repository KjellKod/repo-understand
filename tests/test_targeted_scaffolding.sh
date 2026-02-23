#!/usr/bin/env bash
# Integration tests for lib/targeted-scaffolding.sh
# Bash 3.2 compatible

set -eo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"

# Source dependencies
. "$REPO_DIR/lib/util.sh"
. "$REPO_DIR/lib/targeted-scaffolding.sh"

PASS=0
FAIL=0
FIXTURE_DIR=""
TMP_DIR=""

_setup() {
    FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test-targeted-XXXXXX")
    FIXTURE_DIR=$(cd "$FIXTURE_DIR" && pwd)
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test-targeted-tmp-XXXXXX")
    TMP_DIR=$(cd "$TMP_DIR" && pwd)
}

_teardown() {
    [ -n "$FIXTURE_DIR" ] && rm -rf "$FIXTURE_DIR"
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
}

trap _teardown EXIT

assert_file_exists() {
    local file="$1"
    local msg="$2"
    if [ -f "$file" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $msg" >&2
        echo "  File does not exist: $file" >&2
    fi
}

assert_file_contains() {
    local file="$1"
    local needle="$2"
    local msg="$3"
    if grep -qF -- "$needle" "$file" 2>/dev/null; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $msg" >&2
        echo "  Expected file to contain: $needle" >&2
    fi
}

assert_file_not_contains() {
    local file="$1"
    local needle="$2"
    local msg="$3"
    if grep -qF -- "$needle" "$file" 2>/dev/null; then
        FAIL=$((FAIL + 1))
        echo "FAIL: $msg" >&2
        echo "  Expected file NOT to contain: $needle" >&2
    else
        PASS=$((PASS + 1))
    fi
}

# ─── Tests ────────────────────────────────────────────────────────────────────

test_full_pipeline() {
    _setup

    # Build a fixture repo:
    # src/sms/sms.js -> src/sms/manager.js -> src/pricing/pricing.js
    # src/billing/invoice.js -> src/pricing/pricing.js
    # src/unrelated.js (no connections)
    mkdir -p "$FIXTURE_DIR/src/sms"
    mkdir -p "$FIXTURE_DIR/src/pricing"
    mkdir -p "$FIXTURE_DIR/src/billing"

    cat > "$FIXTURE_DIR/src/sms/sms.js" <<'EOF'
const manager = require('./manager');
// SMS entry point
function sendSMS(number, message) {
    return manager.send(number, message);
}
module.exports = { sendSMS };
EOF

    cat > "$FIXTURE_DIR/src/sms/manager.js" <<'EOF'
const pricing = require('../pricing/pricing');
function send(number, message) {
    const cost = pricing.calculate(number);
    console.log('Sending SMS, cost:', cost);
}
module.exports = { send };
EOF

    cat > "$FIXTURE_DIR/src/pricing/pricing.js" <<'EOF'
function calculate(number) {
    return 0.05;
}
module.exports = { calculate };
EOF

    cat > "$FIXTURE_DIR/src/billing/invoice.js" <<'EOF'
const pricing = require('../pricing/pricing');
function createInvoice() {
    return { amount: pricing.calculate('test') };
}
module.exports = { createInvoice };
EOF

    cat > "$FIXTURE_DIR/src/unrelated.js" <<'EOF'
// This file has nothing to do with SMS
const x = 42;
EOF

    # Create package.json for fallback
    cat > "$FIXTURE_DIR/package.json" <<'EOF'
{ "name": "test-repo", "main": "src/sms/sms.js" }
EOF

    # Run the orchestrator with SMS query
    build_targeted_scaffolding "$FIXTURE_DIR" "Trace the SMS pipeline and how messages are sent" "$TMP_DIR" 2

    # Verify output files exist
    assert_file_exists "$TMP_DIR/targeted_payload.txt" \
        "Payload file should exist"
    assert_file_exists "$TMP_DIR/file_list.txt" \
        "File list should exist"
    assert_file_exists "$TMP_DIR/entry_points.txt" \
        "Entry points file should exist"

    # Verify payload contains expected files
    assert_file_contains "$TMP_DIR/targeted_payload.txt" "--- FILE:" \
        "Payload should contain file separators"
    assert_file_contains "$TMP_DIR/targeted_payload.txt" "sms.js" \
        "Payload should contain sms.js"
    assert_file_contains "$TMP_DIR/targeted_payload.txt" "manager.js" \
        "Payload should contain manager.js"

    # Verify payload does not contain unrelated files
    assert_file_not_contains "$TMP_DIR/targeted_payload.txt" "unrelated.js" \
        "Payload should NOT contain unrelated.js"

    # Verify file count is reasonable (3-6 files)
    local file_count
    file_count=$(wc -l < "$TMP_DIR/file_list.txt" | tr -d ' ')
    if [ "$file_count" -ge 2 ] && [ "$file_count" -le 8 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: Expected 2-8 files, got $file_count" >&2
        cat "$TMP_DIR/file_list.txt" >&2
    fi

    # Verify payload header
    assert_file_contains "$TMP_DIR/targeted_payload.txt" \
        "pre-loaded context" \
        "Payload should contain header text"

    _teardown
}

test_empty_query() {
    _setup

    echo "// main" > "$FIXTURE_DIR/index.js"
    cat > "$FIXTURE_DIR/package.json" <<'EOF'
{ "name": "test-repo", "main": "index.js" }
EOF

    # Run with gibberish query that won't match anything
    build_targeted_scaffolding "$FIXTURE_DIR" "xyzzy" "$TMP_DIR" 2

    assert_file_exists "$TMP_DIR/targeted_payload.txt" \
        "Payload file should exist even with no matches"

    _teardown
}

# ─── Run tests ────────────────────────────────────────────────────────────────

test_full_pipeline
test_empty_query

echo ""
echo "test_targeted_scaffolding.sh: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
