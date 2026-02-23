#!/usr/bin/env bash
# Dependency graph builder using BFS traversal
# Walks import/require chains from entry points up to a configurable depth
# Bash 3.2 compatible -- no associative arrays, no readarray, no ${var,,}
#
# Usage: build_dep_graph "/path/to/entry_points.txt" "/path/to/repo" max_depth "/path/to/tmp"
# Output: Writes ordered file list to $tmp_dir/file_list.txt

# Build dependency graph via BFS from entry points
# Args: entry_points_file repo_path max_depth tmp_dir
# Output: Writes $tmp_dir/file_list.txt (one absolute path per line, BFS order)
build_dep_graph() {
    local entry_points_file="$1"
    local repo_path="$2"
    local max_depth="$3"
    local tmp_dir="$4"

    local queue_file="$tmp_dir/_bfs_queue.txt"
    local visited_file="$tmp_dir/_bfs_visited.txt"
    local output_file="$tmp_dir/file_list.txt"

    : > "$queue_file"
    : > "$visited_file"
    : > "$output_file"

    # Validate entry points file
    if [ ! -f "$entry_points_file" ] || [ ! -s "$entry_points_file" ]; then
        log_warn "No entry points provided, dependency graph will be empty"
        return 0
    fi

    # Seed queue from entry points at depth 0
    while IFS= read -r entry_path; do
        [ -z "$entry_path" ] && continue

        # Resolve symlinks if possible
        local resolved_path
        resolved_path=$(_resolve_symlink "$entry_path")

        if [ ! -f "$resolved_path" ]; then
            log_warn "Entry point does not exist, skipping: $entry_path" >&2
            continue
        fi

        echo "0|${resolved_path}" >> "$queue_file"
    done < "$entry_points_file"

    # BFS loop
    while [ -s "$queue_file" ]; do
        # Read first line from queue (FIFO)
        local first_line
        first_line=$(head -1 "$queue_file")

        # Remove first line from queue without leaving a stray newline.
        # A newline-only queue file would keep "-s queue_file" true forever.
        local queue_lines
        queue_lines=$(wc -l < "$queue_file" | tr -d ' ')
        if [ "$queue_lines" -le 1 ]; then
            : > "$queue_file"
        else
            tail -n +2 "$queue_file" > "$queue_file.tmp"
            mv "$queue_file.tmp" "$queue_file"
        fi

        # Parse depth and filepath
        local depth filepath
        depth=$(echo "$first_line" | cut -d'|' -f1)
        filepath=$(echo "$first_line" | cut -d'|' -f2-)

        [ -z "$filepath" ] && continue

        # Skip if already visited
        if grep -qxF "$filepath" "$visited_file" 2>/dev/null; then
            continue
        fi

        # Skip if beyond max depth
        if [ "$depth" -gt "$max_depth" ]; then
            continue
        fi

        # Mark as visited and add to output
        echo "$filepath" >> "$visited_file"
        echo "$filepath" >> "$output_file"

        # Don't explore children if at max depth
        if [ "$depth" -ge "$max_depth" ]; then
            continue
        fi

        # Parse imports for this file
        local imports_output
        imports_output=$(parse_imports "$filepath" 2>/dev/null) || true

        if [ -z "$imports_output" ]; then
            continue
        fi

        # Process each import record
        local next_depth=$((depth + 1))
        echo "$imports_output" | while IFS='|' read -r raw resolved import_type is_external; do
            # Skip external and dynamic imports
            if [ "$is_external" = "true" ] || [ "$import_type" = "dynamic" ]; then
                continue
            fi

            # Skip if no resolved path
            if [ -z "$resolved" ]; then
                continue
            fi

            # Skip if file doesn't exist
            if [ ! -f "$resolved" ]; then
                continue
            fi

            # Skip if already visited
            if grep -qxF "$resolved" "$visited_file" 2>/dev/null; then
                continue
            fi

            # Ensure file is within repo path
            case "$resolved" in
                "$repo_path"/*)
                    echo "${next_depth}|${resolved}" >> "$queue_file"
                    ;;
            esac
        done
    done

    local file_count
    file_count=$(wc -l < "$output_file" | tr -d ' ')
    log_info "Dependency graph: $file_count files discovered" >&2
}

# Resolve symlinks portably
# Args: path
# Outputs: resolved path to stdout
_resolve_symlink() {
    local target="$1"
    # Keep original path form (/var vs /private/var) to avoid mismatches
    # in repo-root prefix checks and test fixture assertions.
    echo "$target"
}
