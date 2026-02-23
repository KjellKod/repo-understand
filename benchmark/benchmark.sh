#!/usr/bin/env bash
# Benchmark harness for repo-understand
# Measures time, tokens, and accuracy for agent tasks with/without scaffolding
#
# Usage: benchmark.sh <repo-path> <task-file> [--with-scaffolding | --without-scaffolding]
#        benchmark.sh <repo-path> <task-file> --judge <result-file> [--answer-key <file>]
#
# Bash 3.2 compatible. Requires: jq, claude CLI
#
# How it works:
#   --without-scaffolding: Runs claude as an agent with file access on the repo.
#     No generated docs -- the agent must explore the codebase from scratch.
#
#   --with-scaffolding: First generates scaffolding docs into the repo, then
#     runs claude as an agent with file access. The agent can read the generated
#     docs as part of its exploration. Scaffolding is cleaned up after the run.
#
#   --judge: Runs a separate claude pass to score a previous result for accuracy
#     against the task rubric (and optional answer key).

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_UNDERSTAND_DIR="$(dirname "$SCRIPT_DIR")"

# Source utilities
. "$REPO_UNDERSTAND_DIR/lib/util.sh"

# ─── Helpers ─────────────────────────────────────────────────────────────────────

_cleanup_scaffolding() {
    local repo="$1"
    rm -f "$repo/docs/architecture/overview.md"
    rm -f "$repo/docs/architecture/tech-stack.md"
    rm -f "$repo/docs/architecture/directory-map.md"
    rm -f "$repo/agents-content.md"
    rm -f "$repo/doc-structure.md"
    rm -f "$repo/repo-understand.manifest.json"
    # Remove dirs only if empty
    rmdir "$repo/docs/architecture" 2>/dev/null || true
    rmdir "$repo/docs" 2>/dev/null || true
}

# Run judge on a result file. Updates the result JSON in-place with scores.
# Args: <result-file> <task-content> <model> [answer-key-file]
_run_judge() {
    local result_file="$1"
    local task_content="$2"
    local judge_model="$3"
    local answer_key_file="${4:-}"

    local agent_response
    local result_task
    local result_condition
    agent_response=$(jq -r '.response' "$result_file")
    result_task=$(jq -r '.task' "$result_file")
    result_condition=$(jq -r '.condition' "$result_file")

    local answer_key_section=""
    if [ -n "$answer_key_file" ] && [ -f "$answer_key_file" ]; then
        answer_key_section="
--- ANSWER KEY (ground truth) ---
$(cat "$answer_key_file")
"
    fi

    local judge_prompt="You are a benchmark judge. Score the following agent response for accuracy and completeness.

--- TASK ---
${task_content}
${answer_key_section}
--- AGENT RESPONSE ---
${agent_response}

--- INSTRUCTIONS ---
Score the response using the rubric in the task above. Return ONLY a JSON object:
{
  \"accuracy\": <1-5>,
  \"completeness\": <1-5>,
  \"hallucination_count\": <number of fabricated claims>,
  \"reasoning\": \"<brief explanation of scores>\"
}"

    log_info "Judging result: $result_task ($result_condition)"

    local judge_response_file
    judge_response_file=$(mktemp "${TMPDIR:-/tmp}/benchmark-judge-XXXXXX")

    CLAUDECODE='' claude \
        --output-format json \
        --model "$judge_model" \
        --dangerously-skip-permissions \
        --no-session-persistence \
        -p "$judge_prompt" > "$judge_response_file" 2>/dev/null || {
        log_error "Judge pass failed."
        rm -f "$judge_response_file"
        return 1
    }

    local judge_text
    judge_text=$(jq -r '.result // .content // ""' "$judge_response_file")
    rm -f "$judge_response_file"

    # Extract JSON from judge response (may be wrapped in markdown)
    local judge_json
    judge_json=$(echo "$judge_text" | sed -n '/^{/,/^}/p' | head -20)
    if [ -z "$judge_json" ]; then
        judge_json=$(echo "$judge_text" | sed -n '/```json/,/```/p' | sed '1d;$d')
    fi

    if [ -n "$judge_json" ]; then
        local accuracy completeness hallucinations reasoning updated
        accuracy=$(echo "$judge_json" | jq -r '.accuracy // 0')
        completeness=$(echo "$judge_json" | jq -r '.completeness // 0')
        hallucinations=$(echo "$judge_json" | jq -r '.hallucination_count // 0')
        reasoning=$(echo "$judge_json" | jq -r '.reasoning // ""')

        updated=$(jq \
            --argjson accuracy "$accuracy" \
            --argjson completeness "$completeness" \
            --argjson hallucinations "$hallucinations" \
            --arg reasoning "$reasoning" \
            '. + {accuracy: $accuracy, completeness: $completeness, hallucination_count: $hallucinations, judge_reasoning: $reasoning}' \
            "$result_file")
        echo "$updated" > "$result_file"

        log_success "Judge scores added to result file"
        echo ""
        echo "  Accuracy:       $accuracy/5"
        echo "  Completeness:   $completeness/5"
        echo "  Hallucinations: $hallucinations"
        echo "  Reasoning:      $reasoning"
    else
        log_error "Could not parse judge response"
        echo "$judge_text"
        return 1
    fi
}

# ─── Argument parsing ───────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") <repo-path> <task-file> [options]

Benchmark AI agent performance on a task with or without scaffolding.

Modes:
  --with-scaffolding     Run agent with generated scaffolding (default)
  --without-scaffolding  Run agent without scaffolding (baseline)
  --judge <result-file>  Score a previous result for accuracy

Arguments:
  <repo-path>            Path to the repository to analyze
  <task-file>            Path to the benchmark task markdown file

Options:
  --answer-key <file>    Answer key for judge scoring (optional)
  --model <model>        Model to use (default: sonnet)
  --max-budget <usd>     Max spend per run in USD (default: 2.00)
  --no-judge             Skip automatic judge scoring after benchmark

Requires: jq, claude CLI
EOF
    exit 1
}

REPO_PATH=""
TASK_FILE=""
CONDITION="with"
MODE="benchmark"
JUDGE_RESULT_FILE=""
ANSWER_KEY_FILE=""
MODEL="sonnet"
MAX_BUDGET="2.00"
AUTO_JUDGE="true"

while [ $# -gt 0 ]; do
    case "$1" in
        --with-scaffolding) CONDITION="with" ;;
        --without-scaffolding) CONDITION="without" ;;
        --judge)
            MODE="judge"
            shift
            [ $# -eq 0 ] && { log_error "--judge requires a result file"; usage; }
            JUDGE_RESULT_FILE="$1"
            ;;
        --answer-key)
            shift
            [ $# -eq 0 ] && { log_error "--answer-key requires a file"; usage; }
            ANSWER_KEY_FILE="$1"
            ;;
        --model)
            shift
            [ $# -eq 0 ] && { log_error "--model requires a value"; usage; }
            MODEL="$1"
            ;;
        --max-budget)
            shift
            [ $# -eq 0 ] && { log_error "--max-budget requires a value"; usage; }
            MAX_BUDGET="$1"
            ;;
        --no-judge) AUTO_JUDGE="false" ;;
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

# Check dependencies
require_command "jq" "brew install jq"
require_command "claude" "See https://docs.anthropic.com/en/docs/claude-code"

# ─── Setup ───────────────────────────────────────────────────────────────────────

TASK_NAME=$(basename "$TASK_FILE" .md)
RESULTS_DIR="$SCRIPT_DIR/results"
ensure_dir "$RESULTS_DIR"

TASK_CONTENT=$(cat "$TASK_FILE")

# ─── Judge mode ──────────────────────────────────────────────────────────────────

if [ "$MODE" = "judge" ]; then
    [ -f "$JUDGE_RESULT_FILE" ] || { log_error "Result file not found: $JUDGE_RESULT_FILE"; exit 1; }
    _run_judge "$JUDGE_RESULT_FILE" "$TASK_CONTENT" "$MODEL" "$ANSWER_KEY_FILE"
    exit $?
fi

# ─── Benchmark mode ──────────────────────────────────────────────────────────────

SCAFFOLD_HINT=""
CLEANUP_SCAFFOLD="false"

if [ "$CONDITION" = "with" ]; then
    log_info "Generating scaffolding..."

    # Generate scaffolding into the repo so the agent discovers it naturally
    if [ ! -f "$REPO_PATH/repo-understand.manifest.json" ]; then
        bash "$REPO_UNDERSTAND_DIR/repo-understand.sh" "$REPO_PATH" 2>/dev/null
        CLEANUP_SCAFFOLD="true"
    else
        log_info "Scaffolding already exists in repo, using existing"
    fi

    SCAFFOLD_HINT="

This repository has pre-generated documentation to help you understand it.
Start by reading these files before exploring the codebase:
- docs/architecture/overview.md
- docs/architecture/tech-stack.md
- docs/architecture/directory-map.md
- agents-content.md
- doc-structure.md
"
fi

# Build the agent prompt
AGENT_PROMPT="You are analyzing the repository at: $REPO_PATH
${SCAFFOLD_HINT}
--- TASK ---
${TASK_CONTENT}

Explore the repository using your tools (Read, Glob, Grep) to answer the task
thoroughly. Provide a complete, well-structured answer."

# ─── Execute ─────────────────────────────────────────────────────────────────────

START_TIME=$(date +%s)
RESULT_FILE="$RESULTS_DIR/$(date +%Y%m%d_%H%M%S)_${TASK_NAME}_${CONDITION}.json"

log_info "Executing benchmark: $TASK_NAME ($CONDITION scaffolding)"
log_info "Model: $MODEL | Budget cap: \$$MAX_BUDGET"

RESPONSE_FILE=$(mktemp "${TMPDIR:-/tmp}/benchmark-response-XXXXXX")

CLAUDECODE='' claude \
    --output-format json \
    --model "$MODEL" \
    --dangerously-skip-permissions \
    --no-session-persistence \
    --max-budget-usd "$MAX_BUDGET" \
    --add-dir "$REPO_PATH" \
    --allowedTools "Read Glob Grep" \
    -p "$AGENT_PROMPT" > "$RESPONSE_FILE" 2>/dev/null || {
    log_error "Claude agent run failed."
    rm -f "$RESPONSE_FILE"
    if [ "$CLEANUP_SCAFFOLD" = "true" ]; then
        _cleanup_scaffolding "$REPO_PATH"
    fi
    exit 1
}

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Save raw response for debugging (kept alongside results)
RAW_RESPONSE_FILE="$RESULTS_DIR/$(date +%Y%m%d_%H%M%S)_${TASK_NAME}_${CONDITION}_raw.json"
cp "$RESPONSE_FILE" "$RAW_RESPONSE_FILE"

# Extract metrics from Claude CLI JSON output
# input_tokens only counts non-cached tokens; include cached tokens for real total
INPUT_TOKENS=$(jq -r '[.usage.input_tokens // 0, .usage.cache_creation_input_tokens // 0, .usage.cache_read_input_tokens // 0] | add' "$RESPONSE_FILE")
OUTPUT_TOKENS=$(jq -r '(.usage.output_tokens // 0)' "$RESPONSE_FILE")
RESPONSE_TEXT=$(jq -r '(.result // "")' "$RESPONSE_FILE")
NUM_TURNS=$(jq -r '(.num_turns // 0)' "$RESPONSE_FILE")
COST_USD=$(jq -r '(.total_cost_usd // 0)' "$RESPONSE_FILE")
SUBTYPE=$(jq -r '(.subtype // "unknown")' "$RESPONSE_FILE")

# Warn if agent hit budget cap before finishing
if [ "$SUBTYPE" = "error_max_budget_usd" ]; then
    log_error "Agent hit budget cap (\$$MAX_BUDGET) before completing. Response may be empty."
    log_error "Try increasing --max-budget (e.g. --max-budget 2.00)"
fi
rm -f "$RESPONSE_FILE"

log_info "Raw response saved: $RAW_RESPONSE_FILE"

# Clean up scaffolding if we generated it
if [ "$CLEANUP_SCAFFOLD" = "true" ]; then
    _cleanup_scaffolding "$REPO_PATH"
fi

# ─── Save results ────────────────────────────────────────────────────────────────

jq -n \
    --arg task "$TASK_NAME" \
    --arg condition "$CONDITION" \
    --arg repo "$REPO_PATH" \
    --arg model "$MODEL" \
    --arg status "$SUBTYPE" \
    --arg timestamp "$(iso_timestamp)" \
    --argjson input_tokens "$INPUT_TOKENS" \
    --argjson output_tokens "$OUTPUT_TOKENS" \
    --argjson duration_seconds "$DURATION" \
    --argjson num_turns "$NUM_TURNS" \
    --argjson cost_usd "$COST_USD" \
    --arg response "$RESPONSE_TEXT" \
    '{
        task: $task,
        condition: $condition,
        repo: $repo,
        model: $model,
        status: $status,
        timestamp: $timestamp,
        input_tokens: $input_tokens,
        output_tokens: $output_tokens,
        total_tokens: ($input_tokens + $output_tokens),
        duration_seconds: $duration_seconds,
        num_turns: $num_turns,
        cost_usd: $cost_usd,
        response: $response
    }' > "$RESULT_FILE"

log_success "Benchmark complete"
echo ""
echo "Results:"
echo "  Task:          $TASK_NAME"
echo "  Condition:     $CONDITION scaffolding"
echo "  Model:         $MODEL"
echo "  Status:        $SUBTYPE"
echo "  Input tokens:  $INPUT_TOKENS (including cached)"
echo "  Output tokens: $OUTPUT_TOKENS"
echo "  Total tokens:  $((INPUT_TOKENS + OUTPUT_TOKENS))"
echo "  Agent turns:   $NUM_TURNS"
echo "  Cost:          \$$COST_USD"
echo "  Duration:      ${DURATION}s"
echo "  Saved to:      $RESULT_FILE"

# Auto-judge unless --no-judge was passed
if [ "$AUTO_JUDGE" = "true" ]; then
    echo ""
    _run_judge "$RESULT_FILE" "$TASK_CONTENT" "$MODEL" "$ANSWER_KEY_FILE" || true
else
    echo ""
    echo "To judge accuracy:"
    echo "  $(basename "$0") $REPO_PATH $TASK_FILE --judge $RESULT_FILE"
fi
