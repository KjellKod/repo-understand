#!/usr/bin/env bash
# Tests for benchmark/benchmark-suite.sh guardrails
# Bash 3.2 compatible

set -eo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"
SUITE_SCRIPT="$REPO_DIR/benchmark/benchmark-suite.sh"

PASS=0
FAIL=0

assert_fails_with() {
    local cmd="$1"
    local expected="$2"
    local label="$3"
    local output

    if output=$(eval "$cmd" 2>&1); then
        FAIL=$((FAIL + 1))
        echo "FAIL: $label" >&2
        echo "  Command unexpectedly succeeded" >&2
        return
    fi

    if echo "$output" | grep -qF "$expected"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label" >&2
        echo "  Expected output to contain: $expected" >&2
        echo "  Got: $output" >&2
    fi
}

test_requires_task_prompt_section() {
    local fixture_repo challenge_file output_dir
    fixture_repo=$(mktemp -d "${TMPDIR:-/tmp}/test-suite-repo-XXXXXX")
    challenge_file=$(mktemp "${TMPDIR:-/tmp}/test-suite-challenge-XXXXXX.md")
    output_dir=$(mktemp -d "${TMPDIR:-/tmp}/test-suite-output-XXXXXX")
    echo "# Benchmark Task" > "$challenge_file"
    echo "" >> "$challenge_file"
    echo "No prompt header here." >> "$challenge_file"

    assert_fails_with \
        "bash \"$SUITE_SCRIPT\" \"$fixture_repo\" \"$challenge_file\" --output-dir \"$output_dir\" --no-judge" \
        "must contain a markdown section header: ## Task Prompt" \
        "suite should reject challenge files without Task Prompt section"

    rm -rf "$fixture_repo"
    rm -f "$challenge_file"
    rm -rf "$output_dir"
}

test_rejects_same_filename_inside_repo() {
    local fixture_repo challenge_dir challenge_file output_dir
    fixture_repo=$(mktemp -d "${TMPDIR:-/tmp}/test-suite-repo-XXXXXX")
    challenge_dir=$(mktemp -d "${TMPDIR:-/tmp}/test-suite-challenges-XXXXXX")
    output_dir=$(mktemp -d "${TMPDIR:-/tmp}/test-suite-output-XXXXXX")
    challenge_file="$challenge_dir/benchmark-collision.md"

    mkdir -p "$fixture_repo/ideas"
    cat > "$fixture_repo/ideas/benchmark-collision.md" <<'EOF'
# In-repo challenge copy
## Task Prompt
> Prompt inside repo copy
EOF

    cat > "$challenge_file" <<'EOF'
# External challenge
## Task Prompt
> Prompt outside repo
EOF

    assert_fails_with \
        "bash \"$SUITE_SCRIPT\" \"$fixture_repo\" \"$challenge_file\" --output-dir \"$output_dir\" --no-judge" \
        "A file with the same name exists in target repo (unsafe)" \
        "suite should reject external challenge when same filename exists in repo"

    rm -rf "$fixture_repo"
    rm -rf "$challenge_dir"
    rm -rf "$output_dir"
}

test_requires_non_empty_task_prompt() {
    local fixture_repo challenge_file output_dir
    fixture_repo=$(mktemp -d "${TMPDIR:-/tmp}/test-suite-repo-XXXXXX")
    challenge_file=$(mktemp "${TMPDIR:-/tmp}/test-suite-challenge-XXXXXX.md")
    output_dir=$(mktemp -d "${TMPDIR:-/tmp}/test-suite-output-XXXXXX")
    cat > "$challenge_file" <<'EOF'
# Benchmark Task
## Task Prompt

## Expected Answer
Hidden answer text
EOF

    assert_fails_with \
        "bash \"$SUITE_SCRIPT\" \"$fixture_repo\" \"$challenge_file\" --output-dir \"$output_dir\" --no-judge" \
        "Task Prompt section exists but is empty" \
        "suite should reject empty Task Prompt section"

    rm -rf "$fixture_repo"
    rm -f "$challenge_file"
    rm -rf "$output_dir"
}

test_requires_task_prompt_section
test_rejects_same_filename_inside_repo
test_requires_non_empty_task_prompt

echo ""
echo "test_benchmark_suite.sh: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
