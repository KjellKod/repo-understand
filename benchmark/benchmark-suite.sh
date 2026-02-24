#!/usr/bin/env bash
# One-shot benchmark suite runner:
# clean -> without -> clean -> with -> clean -> targeted -> clean -> report
#
# Usage:
#   benchmark-suite.sh <repo-path> <challenge-file|challenge-dir> [options]
#
# Bash 3.2 compatible. Requires: jq, claude CLI

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_UNDERSTAND_DIR="$(dirname "$SCRIPT_DIR")"
. "$REPO_UNDERSTAND_DIR/lib/util.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <repo-path> <challenge-file|challenge-dir> [options]

Runs both benchmark conditions for each challenge:
  clean -> without -> clean -> with -> clean -> report

Challenge input:
  - If a file is provided, run that one challenge
  - If a directory is provided, run all benchmark-*.md files in that directory

Safety defaults:
  - Challenge files must be OUTSIDE the target repo path.
  - The file must contain a markdown section named "## Task Prompt".
  - Only that section is sent to the benchmark agent.
  - The full file is used as judge answer key.
  - Reports/results are stored outside the target repo by default.

Options:
  --model <model>               Model to use (default: opus)
  --max-budget <usd>            Max spend per run in USD (default: 5.00)
  --output-dir <dir>            Root output dir for per-challenge reports
                                (default: benchmark/results-by-challenge)
  --no-judge                    Skip judge pass
  --allow-task-file-in-repo     Allow challenge file inside target repo (unsafe)
  --help, -h                    Show this help
EOF
}

abs_path() {
    local input_path="$1"
    [ -e "$input_path" ] || return 1
    (
        cd "$(dirname "$input_path")" >/dev/null 2>&1 || exit 1
        printf "%s/%s\n" "$(pwd)" "$(basename "$input_path")"
    )
}

is_path_in_repo() {
    local candidate="$1"
    local repo="$2"
    case "$candidate" in
        "$repo"|"$repo"/*) return 0 ;;
        *) return 1 ;;
    esac
}

cleanup_scaffolding() {
    local repo="$1"
    rm -f "$repo/docs/architecture/overview.md"
    rm -f "$repo/docs/architecture/tech-stack.md"
    rm -f "$repo/docs/architecture/directory-map.md"
    rm -f "$repo/agents-content.md"
    rm -f "$repo/doc-structure.md"
    rm -f "$repo/repo-understand.manifest.json"
    rmdir "$repo/docs/architecture" 2>/dev/null || true
    rmdir "$repo/docs" 2>/dev/null || true
}

extract_task_prompt() {
    local challenge_file="$1"
    local out_file="$2"

    awk '
        BEGIN { in_prompt=0; found=0 }
        /^##[[:space:]]+Task[[:space:]]+Prompt[[:space:]]*$/ { in_prompt=1; found=1; next }
        /^##[[:space:]]+/ { if (in_prompt==1) exit }
        { if (in_prompt==1) print }
        END { if (found==0) exit 2 }
    ' "$challenge_file" > "$out_file"
    local rc=$?
    if [ "$rc" -eq 2 ]; then
        return 2
    fi
    if [ "$rc" -ne 0 ]; then
        return 1
    fi

    # Trim leading/trailing blank lines.
    sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$out_file" 2>/dev/null || true
    sed -i '' '1{/^$/d;}' "$out_file" 2>/dev/null || true

    if [ ! -s "$out_file" ]; then
        return 3
    fi
    return 0
}

basename_exists_in_repo() {
    local candidate="$1"
    local repo="$2"
    local base_name
    base_name="$(basename "$candidate")"
    if rg --files "$repo" 2>/dev/null | rg -q "/${base_name}$"; then
        return 0
    fi
    return 1
}

slugify_name() {
    local raw="$1"
    echo "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g' \
        | sed -E 's/^-+|-+$//g'
}

run_condition() {
    local condition="$1"
    local repo="$2"
    local prompt_file="$3"
    local challenge_file="$4"
    local results_dir="$5"
    local task_name="$6"

    cleanup_scaffolding "$repo"

    if [ "$NO_JUDGE" = "true" ]; then
        bash "$SCRIPT_DIR/benchmark.sh" "$repo" "$prompt_file" \
            "--${condition}" \
            --model "$MODEL" \
            --max-budget "$MAX_BUDGET" \
            --results-dir "$results_dir" \
            --task-name "$task_name" \
            --answer-key "$challenge_file" \
            --no-judge
    else
        bash "$SCRIPT_DIR/benchmark.sh" "$repo" "$prompt_file" \
            "--${condition}" \
            --model "$MODEL" \
            --max-budget "$MAX_BUDGET" \
            --results-dir "$results_dir" \
            --task-name "$task_name" \
            --answer-key "$challenge_file"
    fi
}

REPO_PATH=""
CHALLENGE_INPUT=""
MODEL="opus"
MAX_BUDGET="5.00"
NO_JUDGE="false"
ALLOW_TASK_FILE_IN_REPO="false"
OUTPUT_DIR="$SCRIPT_DIR/results-by-challenge"
TMP_FILES=""

while [ $# -gt 0 ]; do
    case "$1" in
        --model)
            shift
            [ $# -eq 0 ] && { log_error "--model requires a value"; usage; exit 1; }
            MODEL="$1"
            ;;
        --max-budget)
            shift
            [ $# -eq 0 ] && { log_error "--max-budget requires a value"; usage; exit 1; }
            MAX_BUDGET="$1"
            ;;
        --output-dir)
            shift
            [ $# -eq 0 ] && { log_error "--output-dir requires a path"; usage; exit 1; }
            OUTPUT_DIR="$1"
            ;;
        --no-judge)
            NO_JUDGE="true"
            ;;
        --allow-task-file-in-repo)
            ALLOW_TASK_FILE_IN_REPO="true"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [ -z "$REPO_PATH" ]; then
                REPO_PATH="$1"
            elif [ -z "$CHALLENGE_INPUT" ]; then
                CHALLENGE_INPUT="$1"
            else
                log_error "Unexpected argument: $1"
                usage
                exit 1
            fi
            ;;
    esac
    shift
done

[ -z "$REPO_PATH" ] && { log_error "Missing <repo-path>"; usage; exit 1; }
[ -z "$CHALLENGE_INPUT" ] && { log_error "Missing <challenge-file|challenge-dir>"; usage; exit 1; }

REPO_PATH="$(cd "$REPO_PATH" 2>/dev/null && pwd)" || { log_error "Invalid repo path"; exit 1; }
CHALLENGE_INPUT="$(abs_path "$CHALLENGE_INPUT")" || { log_error "Could not resolve challenge input path"; exit 1; }

OUTPUT_DIR="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)" || {
    log_error "Could not create output dir: $OUTPUT_DIR"
    exit 1
}

require_command "jq" "brew install jq"
require_command "claude" "See https://docs.anthropic.com/en/docs/claude-code"

cleanup_tmp() {
    if [ -n "$TMP_FILES" ]; then
        # shellcheck disable=SC2086
        rm -f $TMP_FILES
    fi
}
trap cleanup_tmp EXIT

CHALLENGE_FILES=""
if [ -d "$CHALLENGE_INPUT" ]; then
    while IFS= read -r f; do
        CHALLENGE_FILES="${CHALLENGE_FILES}${f}
"
    done < <(ls -1 "$CHALLENGE_INPUT"/benchmark-*.md 2>/dev/null || true)
else
    [ -f "$CHALLENGE_INPUT" ] || { log_error "Challenge file not found: $CHALLENGE_INPUT"; exit 1; }
    CHALLENGE_FILES="$CHALLENGE_INPUT"
fi

[ -z "$CHALLENGE_FILES" ] && {
    log_error "No challenge files found. Expected benchmark-*.md"
    exit 1
}

while IFS= read -r CHALLENGE_FILE; do
    [ -z "$CHALLENGE_FILE" ] && continue
    CHALLENGE_FILE="$(abs_path "$CHALLENGE_FILE")" || {
        log_error "Could not resolve challenge file path: $CHALLENGE_FILE"
        exit 1
    }

    if [ "$ALLOW_TASK_FILE_IN_REPO" != "true" ]; then
        if is_path_in_repo "$CHALLENGE_FILE" "$REPO_PATH"; then
            log_error "Challenge file is inside benchmark target repo (unsafe): $CHALLENGE_FILE"
            exit 1
        fi
        if basename_exists_in_repo "$CHALLENGE_FILE" "$REPO_PATH"; then
            log_error "A file with the same name exists in target repo (unsafe): $(basename "$CHALLENGE_FILE")"
            log_error "Rename/move the challenge file or remove the in-repo copy."
            exit 1
        fi
    fi

    challenge_base="$(basename "$CHALLENGE_FILE" .md)"
    challenge_slug="$(slugify_name "$challenge_base")"
    results_dir="$OUTPUT_DIR/$challenge_slug"
    mkdir -p "$results_dir"
    rm -f "$results_dir"/*.json "$results_dir"/benchmark-report.md 2>/dev/null || true

    task_prompt_tmp=$(mktemp "${TMPDIR:-/tmp}/benchmark-task-prompt-XXXXXX.md")
    TMP_FILES="$TMP_FILES $task_prompt_tmp"

    extract_rc=0
    extract_task_prompt "$CHALLENGE_FILE" "$task_prompt_tmp" || extract_rc=$?
    if [ "$extract_rc" -eq 2 ]; then
        log_error "Challenge file must contain a markdown section header: ## Task Prompt"
        exit 1
    elif [ "$extract_rc" -eq 3 ]; then
        log_error "Task Prompt section exists but is empty: $CHALLENGE_FILE"
        exit 1
    elif [ "$extract_rc" -ne 0 ]; then
        log_error "Failed to parse Task Prompt from: $CHALLENGE_FILE"
        exit 1
    fi

    log_info "Running challenge: $challenge_base"
    run_condition "without-scaffolding" "$REPO_PATH" "$task_prompt_tmp" "$CHALLENGE_FILE" "$results_dir" "$challenge_base"
    run_condition "with-scaffolding" "$REPO_PATH" "$task_prompt_tmp" "$CHALLENGE_FILE" "$results_dir" "$challenge_base"
    cleanup_scaffolding "$REPO_PATH"

    bash "$SCRIPT_DIR/report.sh" --results-dir "$results_dir"

    log_success "Challenge complete: $challenge_base"
    echo "  Report: $results_dir/benchmark-report.md"
done <<EOF
$CHALLENGE_FILES
EOF

log_success "Benchmark suite complete"
echo "Output root: $OUTPUT_DIR"
