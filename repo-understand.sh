#!/usr/bin/env bash
# repo-understand.sh -- Analyze a git repository and generate AI agent scaffolding
#
# Usage: repo-understand.sh <repo-path> [--output <dir>] [--dry-run]
#
# Bash 3.2 compatible. Requires: jq
# No associative arrays, no readarray, no ${var,,}

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source libraries
. "$SCRIPT_DIR/lib/util.sh"
. "$SCRIPT_DIR/lib/analyzers/structure.sh"
. "$SCRIPT_DIR/lib/analyzers/tech-stack.sh"
. "$SCRIPT_DIR/lib/analyzers/dependencies.sh"
. "$SCRIPT_DIR/lib/analyzers/patterns.sh"
. "$SCRIPT_DIR/lib/analyzers/git-insights.sh"
. "$SCRIPT_DIR/lib/generators/architecture-overview.sh"
. "$SCRIPT_DIR/lib/generators/tech-stack-doc.sh"
. "$SCRIPT_DIR/lib/generators/directory-map.sh"
. "$SCRIPT_DIR/lib/generators/agents-content.sh"
. "$SCRIPT_DIR/lib/generators/doc-structure.sh"

# ─── Argument parsing ───────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") <repo-path> [--output <dir>] [--dry-run]

Analyze a git repository and generate AI agent scaffolding documentation.

Arguments:
  <repo-path>       Path to the repository to analyze
  --output <dir>    Output directory (default: <repo-path>)
  --dry-run         Show what would be generated without writing files

Outputs:
  docs/architecture/overview.md      Architecture overview
  docs/architecture/tech-stack.md    Technology stack
  docs/architecture/directory-map.md Annotated directory tree
  agents-content.md                  Agent guidance with architecture boundaries
  doc-structure.md                   Documentation navigation map
  repo-understand.manifest.json      Generation metadata

Requires: jq (https://jqlang.github.io/jq/)
EOF
    exit 1
}

REPO_PATH=""
OUTPUT_DIR=""
DRY_RUN="false"

while [ $# -gt 0 ]; do
    case "$1" in
        --output)
            shift
            [ $# -eq 0 ] && { log_error "--output requires an argument"; usage; }
            OUTPUT_DIR="$1"
            ;;
        --dry-run)
            DRY_RUN="true"
            ;;
        --help|-h)
            usage
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$REPO_PATH" ]; then
                REPO_PATH="$1"
            else
                log_error "Unexpected argument: $1"
                usage
            fi
            ;;
    esac
    shift
done

[ -z "$REPO_PATH" ] && { log_error "Missing required argument: <repo-path>"; usage; }

# ─── Validation ──────────────────────────────────────────────────────────────────

# Resolve to absolute path
REPO_PATH="$(cd "$REPO_PATH" 2>/dev/null && pwd)" || {
    log_error "Repository path does not exist: $REPO_PATH"
    exit 1
}

[ -d "$REPO_PATH" ] || { log_error "Not a directory: $REPO_PATH"; exit 1; }

# Default output dir to repo path
[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="$REPO_PATH"
OUTPUT_DIR="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)"

# Check for jq
require_command "jq" "brew install jq  (macOS)  or  apt-get install jq  (Linux)"

# ─── Start ───────────────────────────────────────────────────────────────────────

START_TIME=$(date +%s)
TIMESTAMP=$(iso_timestamp)
GIT_SHA=$(git_sha "$REPO_PATH")
TOTAL_FILES=$(count_files "$REPO_PATH")

printf "\n"
log_info "repo-understand: analyzing $(basename "$REPO_PATH")"
log_info "Path:       $REPO_PATH"
log_info "Output:     $OUTPUT_DIR"
log_info "Files:      $TOTAL_FILES"
log_info "Git SHA:    $GIT_SHA"
log_info "Timestamp:  $TIMESTAMP"
printf "\n"

if [ "$DRY_RUN" = "true" ]; then
    log_info "DRY RUN -- would generate the following files:"
    echo "  $OUTPUT_DIR/docs/architecture/overview.md"
    echo "  $OUTPUT_DIR/docs/architecture/tech-stack.md"
    echo "  $OUTPUT_DIR/docs/architecture/directory-map.md"
    echo "  $OUTPUT_DIR/agents-content.md"
    echo "  $OUTPUT_DIR/doc-structure.md"
    echo "  $OUTPUT_DIR/repo-understand.manifest.json"
    exit 0
fi

# Create temp directory for intermediate JSON
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/repo-understand.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

# ─── Phase 1: Analysis ──────────────────────────────────────────────────────────

log_info "Phase 1: Running analyzers..."
printf "\n"

analyze_structure "$REPO_PATH" "$TMP_DIR"
analyze_tech_stack "$REPO_PATH" "$TMP_DIR"
analyze_dependencies "$REPO_PATH" "$TMP_DIR"
analyze_patterns "$REPO_PATH" "$TMP_DIR"
analyze_git_insights "$REPO_PATH" "$TMP_DIR"

printf "\n"

# ─── Phase 2: Generation ────────────────────────────────────────────────────────

log_info "Phase 2: Generating artifacts..."
printf "\n"

ensure_dir "$OUTPUT_DIR/docs/architecture"

generate_architecture_overview "$TMP_DIR" "$OUTPUT_DIR" "$GIT_SHA" "$TIMESTAMP"
generate_tech_stack_doc "$TMP_DIR" "$OUTPUT_DIR" "$GIT_SHA" "$TIMESTAMP"
generate_directory_map "$TMP_DIR" "$OUTPUT_DIR" "$GIT_SHA" "$TIMESTAMP" "$REPO_PATH"
generate_agents_content "$TMP_DIR" "$OUTPUT_DIR" "$GIT_SHA" "$TIMESTAMP"
generate_doc_structure "$TMP_DIR" "$OUTPUT_DIR" "$GIT_SHA" "$TIMESTAMP" "$REPO_PATH"

# ─── Phase 3: Manifest ──────────────────────────────────────────────────────────

END_TIME=$(date +%s)
SCAN_DURATION=$((END_TIME - START_TIME))

jq -n \
    --arg version "0.0.2" \
    --arg generated_at "$TIMESTAMP" \
    --arg git_sha "$GIT_SHA" \
    --arg repo_path "$REPO_PATH" \
    --argjson total_files "$TOTAL_FILES" \
    --argjson scan_duration_seconds "$SCAN_DURATION" \
    '{
        version: $version,
        generated_at: $generated_at,
        git_sha: $git_sha,
        repo_path: $repo_path,
        total_files: $total_files,
        scan_duration_seconds: $scan_duration_seconds
    }' > "$OUTPUT_DIR/repo-understand.manifest.json"

# ─── Summary ─────────────────────────────────────────────────────────────────────

printf "\n"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "repo-understand complete:"
echo "  Repository: $(basename "$REPO_PATH") ($TOTAL_FILES files)"
echo "  Scan time:  ${SCAN_DURATION}s"
echo "  Generated:  5 artifacts + manifest"

# File sizes
for artifact in \
    "docs/architecture/overview.md" \
    "docs/architecture/tech-stack.md" \
    "docs/architecture/directory-map.md" \
    "agents-content.md" \
    "doc-structure.md"; do
    local_path="$OUTPUT_DIR/$artifact"
    if [ -f "$local_path" ]; then
        local_size=$(file_size_bytes "$local_path")
        printf "    %-40s (%s)\n" "$artifact" "$(human_size "$local_size")"
    fi
done

echo "  Commit SHA at scan: $GIT_SHA"
echo "  To update: re-run this command"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
