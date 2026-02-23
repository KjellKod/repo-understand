#!/usr/bin/env bash
# Targeted scaffolding orchestrator
# Coordinates entry point detection, dependency graph building, and payload assembly
# Bash 3.2 compatible -- no associative arrays, no readarray, no ${var,,}
#
# Usage: build_targeted_scaffolding "/path/to/repo" "task content" "/path/to/tmp" [max_depth]
# Output: Writes $tmp_dir/targeted_payload.txt and $tmp_dir/file_list.txt

# Use BASH_SOURCE so this works when sourced from another script.
TARGETED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
. "$TARGETED_SCRIPT_DIR/analyzers/imports.sh"
. "$TARGETED_SCRIPT_DIR/targeted/entry-points.sh"
. "$TARGETED_SCRIPT_DIR/targeted/dep-graph.sh"

# Patterns to exclude from scaffolding payload
_EXCLUDE_PATTERNS="node_modules|/test/|/tests/|/__tests__/|/spec/|\.test\.|\.spec\.|/dist/|/build/|/\.git/|\.min\."

# Max file size to include (100KB)
_MAX_FILE_SIZE=102400

# Max total payload size before truncation (400KB)
_MAX_PAYLOAD_SIZE=409600

# Max lines per file when truncating
_TRUNCATE_LINES=500

# Build targeted scaffolding payload
# Args: repo_path task_content tmp_dir [max_depth]
# Output: Writes $tmp_dir/targeted_payload.txt and $tmp_dir/file_list.txt
build_targeted_scaffolding() {
    local repo_path="$1"
    local task_content="$2"
    local tmp_dir="$3"
    local max_depth="${4:-2}"

    local payload_file="$tmp_dir/targeted_payload.txt"
    local included_list="$tmp_dir/included_file_list.txt"

    log_info "Building targeted scaffolding (depth=$max_depth)..."

    # Step 1: Detect entry points
    detect_entry_points "$task_content" "$repo_path" "$tmp_dir"

    if [ ! -s "$tmp_dir/entry_points.txt" ]; then
        log_warn "No entry points detected, payload will be empty"
        echo "" > "$payload_file"
        : > "$tmp_dir/file_list.txt"
        : > "$included_list"
        return 0
    fi

    log_info "Entry points:"
    while IFS= read -r ep; do
        local rel_path="${ep#$repo_path/}"
        log_info "  $rel_path"
    done < "$tmp_dir/entry_points.txt"

    # Step 2: Build dependency graph
    build_dep_graph "$tmp_dir/entry_points.txt" "$repo_path" "$max_depth" "$tmp_dir"

    if [ ! -s "$tmp_dir/file_list.txt" ]; then
        log_warn "Dependency graph is empty, payload will be empty"
        echo "" > "$payload_file"
        : > "$included_list"
        return 0
    fi

    # Step 3: Assemble payload
    _assemble_payload "$repo_path" "$tmp_dir/file_list.txt" "$payload_file" "$included_list"

    local file_count
    file_count=$(wc -l < "$included_list" | tr -d ' ')
    local payload_size
    payload_size=$(wc -c < "$payload_file" | tr -d ' ')

    log_info "Targeted scaffolding: $file_count files, $(human_size "$payload_size") payload"

    return 0
}

# Assemble file contents into a payload
# Args: repo_path file_list_path payload_path included_file_list_path
_assemble_payload() {
    local repo_path="$1"
    local file_list="$2"
    local payload_path="$3"
    local included_file_list="$4"

    local total_size=0
    local truncating="false"
    : > "$included_file_list"

    # Write header
    cat > "$payload_path" <<'HEADER'
The following source files are pre-loaded context for your analysis.
These are the files most relevant to the task, discovered by import/dependency tracing.

HEADER

    while IFS= read -r filepath; do
        [ -z "$filepath" ] && continue

        # Get relative path
        local rel_path="${filepath#$repo_path/}"

        # Check exclude patterns
        if echo "$rel_path" | grep -qE "$_EXCLUDE_PATTERNS"; then
            continue
        fi

        # Check file existence
        if [ ! -f "$filepath" ]; then
            continue
        fi

        # Check file size
        local fsize
        fsize=$(wc -c < "$filepath" | tr -d ' ')
        if [ "$fsize" -gt "$_MAX_FILE_SIZE" ]; then
            log_warn "Skipping large file ($fsize bytes): $rel_path"
            continue
        fi

        # Check if we need to start truncating
        total_size=$((total_size + fsize))
        if [ "$total_size" -gt "$_MAX_PAYLOAD_SIZE" ]; then
            if [ "$truncating" = "false" ]; then
                log_warn "Payload exceeding 400KB, truncating remaining files to $_TRUNCATE_LINES lines"
                truncating="true"
            fi
        fi

        # Write file separator
        echo "$filepath" >> "$included_file_list"
        echo "--- FILE: $rel_path ---" >> "$payload_path"

        # Write file content (possibly truncated)
        if [ "$truncating" = "true" ]; then
            head -"$_TRUNCATE_LINES" "$filepath" >> "$payload_path"
            local line_count
            line_count=$(wc -l < "$filepath" | tr -d ' ')
            if [ "$line_count" -gt "$_TRUNCATE_LINES" ]; then
                echo "" >> "$payload_path"
                echo "... (truncated at $_TRUNCATE_LINES of $line_count lines)" >> "$payload_path"
            fi
        else
            cat "$filepath" >> "$payload_path"
        fi

        echo "" >> "$payload_path"

    done < "$file_list"
}
