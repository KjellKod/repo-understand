#!/usr/bin/env bash
# Benchmark harness for repo-understand
# Measures token usage for tasks with and without generated scaffolding
#
# Usage: benchmark.sh <repo-path> <task-file> [--with-scaffolding | --without-scaffolding]
#
# Bash 3.2 compatible. Requires: jq, and either `claude` CLI or ANTHROPIC_API_KEY

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_UNDERSTAND_DIR="$(dirname "$SCRIPT_DIR")"

# Source utilities
. "$REPO_UNDERSTAND_DIR/lib/util.sh"

# ─── Argument parsing ───────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") <repo-path> <task-file> [--with-scaffolding | --without-scaffolding]

Benchmark AI agent performance on a task with or without repo-understand scaffolding.

Arguments:
  <repo-path>            Path to the repository to analyze
  <task-file>            Path to the benchmark task markdown file
  --with-scaffolding     Run with generated scaffolding (default)
  --without-scaffolding  Run without scaffolding (baseline)

Requires: jq, and either 'claude' CLI or ANTHROPIC_API_KEY environment variable.
EOF
    exit 1
}

REPO_PATH=""
TASK_FILE=""
CONDITION="with"

while [ $# -gt 0 ]; do
    case "$1" in
        --with-scaffolding) CONDITION="with" ;;
        --without-scaffolding) CONDITION="without" ;;
        --help|-h) usage ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$REPO_PATH" ]; then
                REPO_PATH="$1"
            elif [ -z "$TASK_FILE" ]; then
                TASK_FILE="$1"
            else
                log_error "Unexpected argument: $1"
                usage
            fi
            ;;
    esac
    shift
done

[ -z "$REPO_PATH" ] && { log_error "Missing <repo-path>"; usage; }
[ -z "$TASK_FILE" ] && { log_error "Missing <task-file>"; usage; }

# Validate inputs
REPO_PATH="$(cd "$REPO_PATH" 2>/dev/null && pwd)" || { log_error "Invalid repo path"; exit 1; }
[ -f "$TASK_FILE" ] || { log_error "Task file not found: $TASK_FILE"; exit 1; }

# Check for jq
require_command "jq" "brew install jq"

# ─── Determine API mode ─────────────────────────────────────────────────────────

API_MODE=""
if command -v claude >/dev/null 2>&1; then
    API_MODE="cli"
    log_info "Using claude CLI for benchmarking"
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    API_MODE="api"
    log_info "Using Anthropic HTTP API for benchmarking"
else
    log_error "Neither 'claude' CLI nor ANTHROPIC_API_KEY found."
    log_error "Install claude CLI: npm install -g @anthropic-ai/claude-cli"
    log_error "Or set ANTHROPIC_API_KEY environment variable."
    exit 1
fi

# ─── Setup ───────────────────────────────────────────────────────────────────────

TASK_NAME=$(basename "$TASK_FILE" .md)
RESULTS_DIR="$SCRIPT_DIR/results"
ensure_dir "$RESULTS_DIR"

TASK_CONTENT=$(cat "$TASK_FILE")
SCAFFOLD_CONTEXT=""

if [ "$CONDITION" = "with" ]; then
    log_info "Running with scaffolding..."

    # Generate scaffolding first
    SCAFFOLD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/benchmark-scaffold.XXXXXX")
    trap 'rm -rf "$SCAFFOLD_DIR"' EXIT

    bash "$REPO_UNDERSTAND_DIR/repo-understand.sh" "$REPO_PATH" --output "$SCAFFOLD_DIR" 2>/dev/null

    # Load scaffolding as context
    for artifact in \
        "docs/architecture/overview.md" \
        "docs/architecture/tech-stack.md" \
        "docs/architecture/directory-map.md" \
        "agents-content.md" \
        "doc-structure.md"; do
        if [ -f "$SCAFFOLD_DIR/$artifact" ]; then
            SCAFFOLD_CONTEXT="${SCAFFOLD_CONTEXT}

--- $artifact ---
$(cat "$SCAFFOLD_DIR/$artifact")"
        fi
    done
else
    log_info "Running without scaffolding (baseline)..."
fi

# ─── Build prompt ────────────────────────────────────────────────────────────────

PROMPT="You are analyzing the repository at: $REPO_PATH

${SCAFFOLD_CONTEXT}

--- TASK ---
${TASK_CONTENT}

Please provide a thorough answer to the task above."

# ─── Execute ─────────────────────────────────────────────────────────────────────

START_TIME=$(date +%s)
RESULT_FILE="$RESULTS_DIR/$(date +%Y%m%d_%H%M%S)_${TASK_NAME}_${CONDITION}.json"

log_info "Executing benchmark: $TASK_NAME ($CONDITION scaffolding)"

if [ "$API_MODE" = "cli" ]; then
    # Use claude CLI with JSON output
    RESPONSE_FILE=$(mktemp "${TMPDIR:-/tmp}/benchmark-response.XXXXXX.json")

    claude --output-format json -p "$PROMPT" > "$RESPONSE_FILE" 2>/dev/null || {
        log_error "Claude CLI failed. Check that you are authenticated."
        exit 1
    }

    INPUT_TOKENS=$(jq -r '.usage.input_tokens // 0' "$RESPONSE_FILE")
    OUTPUT_TOKENS=$(jq -r '.usage.output_tokens // 0' "$RESPONSE_FILE")
    RESPONSE_TEXT=$(jq -r '.result // .content // "no response"' "$RESPONSE_FILE")
    rm -f "$RESPONSE_FILE"

elif [ "$API_MODE" = "api" ]; then
    # Use Anthropic HTTP API
    RESPONSE_FILE=$(mktemp "${TMPDIR:-/tmp}/benchmark-response.XXXXXX.json")

    # Escape the prompt for JSON
    ESCAPED_PROMPT=$(echo "$PROMPT" | jq -Rs .)

    curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"claude-sonnet-4-20250514\",
            \"max_tokens\": 4096,
            \"temperature\": 0,
            \"messages\": [{\"role\": \"user\", \"content\": $ESCAPED_PROMPT}]
        }" > "$RESPONSE_FILE" 2>/dev/null || {
        log_error "API call failed."
        exit 1
    }

    INPUT_TOKENS=$(jq -r '.usage.input_tokens // 0' "$RESPONSE_FILE")
    OUTPUT_TOKENS=$(jq -r '.usage.output_tokens // 0' "$RESPONSE_FILE")
    RESPONSE_TEXT=$(jq -r '.content[0].text // "no response"' "$RESPONSE_FILE")
    rm -f "$RESPONSE_FILE"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# ─── Save results ────────────────────────────────────────────────────────────────

# Escape response text for JSON
ESCAPED_RESPONSE=$(echo "$RESPONSE_TEXT" | jq -Rs .)

jq -n \
    --arg task "$TASK_NAME" \
    --arg condition "$CONDITION" \
    --arg repo "$REPO_PATH" \
    --arg timestamp "$(iso_timestamp)" \
    --argjson input_tokens "$INPUT_TOKENS" \
    --argjson output_tokens "$OUTPUT_TOKENS" \
    --argjson duration_seconds "$DURATION" \
    --argjson response "$ESCAPED_RESPONSE" \
    '{
        task: $task,
        condition: $condition,
        repo: $repo,
        timestamp: $timestamp,
        input_tokens: $input_tokens,
        output_tokens: $output_tokens,
        total_tokens: ($input_tokens + $output_tokens),
        duration_seconds: $duration_seconds,
        response: $response
    }' > "$RESULT_FILE"

log_success "Benchmark complete"
echo ""
echo "Results:"
echo "  Task:          $TASK_NAME"
echo "  Condition:     $CONDITION scaffolding"
echo "  Input tokens:  $INPUT_TOKENS"
echo "  Output tokens: $OUTPUT_TOKENS"
echo "  Total tokens:  $((INPUT_TOKENS + OUTPUT_TOKENS))"
echo "  Duration:      ${DURATION}s"
echo "  Saved to:      $RESULT_FILE"
