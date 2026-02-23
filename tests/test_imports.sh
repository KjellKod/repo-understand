#!/usr/bin/env bash
# Tests for lib/analyzers/imports.sh
# Bash 3.2 compatible

set -eo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"

# Source the module under test
. "$REPO_DIR/lib/util.sh"
. "$REPO_DIR/lib/analyzers/imports.sh"

# Test infrastructure
PASS=0
FAIL=0
FIXTURE_DIR=""

_setup() {
    FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test-imports-XXXXXX")
    FIXTURE_DIR=$(cd "$FIXTURE_DIR" && pwd)
}

_teardown() {
    [ -n "$FIXTURE_DIR" ] && rm -rf "$FIXTURE_DIR"
}

trap _teardown EXIT

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $msg" >&2
        echo "  Expected to contain: $needle" >&2
        echo "  Got: $haystack" >&2
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        FAIL=$((FAIL + 1))
        echo "FAIL: $msg" >&2
        echo "  Expected NOT to contain: $needle" >&2
    else
        PASS=$((PASS + 1))
    fi
}

assert_empty() {
    local value="$1"
    local msg="$2"
    if [ -z "$value" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $msg" >&2
        echo "  Expected empty, got: $value" >&2
    fi
}

# ─── Tests ────────────────────────────────────────────────────────────────────

test_parse_commonjs_require() {
    _setup

    # Create fixture files
    echo "// foo module" > "$FIXTURE_DIR/foo.js"
    mkdir -p "$FIXTURE_DIR/mydir"
    echo "// index" > "$FIXTURE_DIR/mydir/index.js"
    echo '{"key": "value"}' > "$FIXTURE_DIR/data.json"

    # Create the file that requires them
    cat > "$FIXTURE_DIR/main.js" <<'EOF'
const foo = require('./foo');
const mydir = require('./mydir');
const data = require('./data.json');
const express = require('express');
const dynamic = require(someVariable);
EOF

    local output
    output=$(parse_imports "$FIXTURE_DIR/main.js")

    # Test relative require resolves to .js
    assert_contains "$output" "./foo|$FIXTURE_DIR/foo.js|commonjs|false" \
        "require('./foo') should resolve to foo.js"

    # Test directory require resolves to /index.js
    assert_contains "$output" "./mydir|$FIXTURE_DIR/mydir/index.js|commonjs|false" \
        "require('./mydir') should resolve to mydir/index.js"

    # Test .json require
    assert_contains "$output" "./data.json|$FIXTURE_DIR/data.json|commonjs|false" \
        "require('./data.json') should resolve to data.json"

    # Test external package
    assert_contains "$output" "express||commonjs|true" \
        "require('express') should be marked external"

    # Test dynamic import
    assert_contains "$output" "someVariable||dynamic|false" \
        "require(variable) should be marked dynamic"

    _teardown
}

test_parse_esm_imports() {
    _setup

    echo "// module" > "$FIXTURE_DIR/module.js"
    mkdir -p "$FIXTURE_DIR/parent"
    echo "// path" > "$FIXTURE_DIR/path.js"
    echo "// side" > "$FIXTURE_DIR/side.js"

    cat > "$FIXTURE_DIR/main.js" <<'EOF'
import foo from './module';
import { bar } from './path';
import './side';
import lodash from 'lodash';
EOF

    local output
    output=$(parse_imports "$FIXTURE_DIR/main.js")

    assert_contains "$output" "./module|$FIXTURE_DIR/module.js|esm|false" \
        "import from './module' should resolve"

    assert_contains "$output" "./path|$FIXTURE_DIR/path.js|esm|false" \
        "import { bar } from './path' should resolve"

    assert_contains "$output" "./side|$FIXTURE_DIR/side.js|esm|false" \
        "import './side' should resolve as side-effect import"

    assert_contains "$output" "lodash||esm|true" \
        "import from 'lodash' should be marked external"

    _teardown
}

test_parse_typescript_extensions() {
    _setup

    # Create .ts and .tsx files (no .js equivalents)
    echo "// ts component" > "$FIXTURE_DIR/component.ts"
    echo "// tsx component" > "$FIXTURE_DIR/widget.tsx"
    mkdir -p "$FIXTURE_DIR/tsdir"
    echo "// index.ts" > "$FIXTURE_DIR/tsdir/index.ts"

    cat > "$FIXTURE_DIR/main.js" <<'EOF'
const comp = require('./component');
const widget = require('./widget');
const tsdir = require('./tsdir');
EOF

    local output
    output=$(parse_imports "$FIXTURE_DIR/main.js")

    assert_contains "$output" "./component|$FIXTURE_DIR/component.ts|commonjs|false" \
        "require('./component') should resolve to .ts"

    assert_contains "$output" "./widget|$FIXTURE_DIR/widget.tsx|commonjs|false" \
        "require('./widget') should resolve to .tsx"

    assert_contains "$output" "./tsdir|$FIXTURE_DIR/tsdir/index.ts|commonjs|false" \
        "require('./tsdir') should resolve to index.ts"

    _teardown
}

test_no_imports() {
    _setup

    cat > "$FIXTURE_DIR/empty.js" <<'EOF'
// This file has no imports
const x = 42;
console.log(x);
EOF

    local output
    output=$(parse_imports "$FIXTURE_DIR/empty.js")

    assert_empty "$output" "File with no imports should produce no output"

    _teardown
}

test_nonexistent_file() {
    local output
    output=$(parse_imports "/nonexistent/path/file.js")

    assert_empty "$output" "Nonexistent file should produce no output"
}

test_type_imports_skipped() {
    _setup

    echo "// types" > "$FIXTURE_DIR/types.ts"

    cat > "$FIXTURE_DIR/main.ts" <<'EOF'
import type { Foo } from './types';
import { Bar } from './types';
EOF

    local output
    output=$(parse_imports "$FIXTURE_DIR/main.ts")

    # Should have exactly one import (the non-type one)
    local count
    count=$(echo "$output" | grep -c "types" || true)

    if [ "$count" -eq 1 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: Expected 1 import line for types, got $count" >&2
        echo "  Output: $output" >&2
    fi

    _teardown
}

# ─── Run tests ────────────────────────────────────────────────────────────────

test_parse_commonjs_require
test_parse_esm_imports
test_parse_typescript_extensions
test_no_imports
test_nonexistent_file
test_type_imports_skipped

echo ""
echo "test_imports.sh: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
