#!/usr/bin/env bash
# Entry point detector for targeted scaffolding
# Extracts keywords from a query and finds matching files in a repo
# Bash 3.2 compatible -- no associative arrays, no readarray, no ${var,,}
#
# Usage: detect_entry_points "query text" "/path/to/repo" "/path/to/tmp"
# Output: Writes 2-5 absolute file paths to $tmp_dir/entry_points.txt

# Stop words to filter from queries
_STOP_WORDS="the a an is to from for of in on at by with and or not it its this that are was were be been being have has had do does did will would shall should may might can could how what where when why who which"

# Check if a word is a stop word
# Args: word
# Returns: 0 if stop word, 1 otherwise
_is_stop_word() {
    local word="$1"
    local sw
    for sw in $_STOP_WORDS; do
        if [ "$word" = "$sw" ]; then
            return 0
        fi
    done
    return 1
}

# Extract keywords from query text
# Args: query_text
# Outputs: space-separated keywords to stdout
_extract_keywords() {
    local query="$1"

    # Lowercase and split on non-alphanumeric characters
    local words
    words=$(echo "$query" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alpha:]' ' ')

    local word
    for word in $words; do
        # Skip short words (< 3 chars) and stop words
        if [ ${#word} -ge 3 ] && ! _is_stop_word "$word"; then
            echo "$word"
        fi
    done | sort -u
}

# Count lines in an entry-point file.
# Args: entry_file
# Outputs: count to stdout
_entry_count() {
    local entry_file="$1"
    if [ ! -f "$entry_file" ]; then
        echo 0
        return 0
    fi
    wc -l < "$entry_file" | tr -d ' '
}

# Append a candidate path if it exists and is not already present.
# Args: entry_file candidate_path max_count
_append_unique_entry() {
    local entry_file="$1"
    local candidate="$2"
    local max_count="${3:-5}"

    [ -z "$candidate" ] && return 0
    [ ! -f "$candidate" ] && return 0

    local count
    count=$(_entry_count "$entry_file")
    if [ "$count" -ge "$max_count" ]; then
        return 0
    fi

    if ! grep -qxF "$candidate" "$entry_file" 2>/dev/null; then
        echo "$candidate" >> "$entry_file"
    fi
}

# Ensure we emit at least min_count entry points when possible.
# Args: repo_path entry_file [min_count] [max_count]
_ensure_min_entry_points() {
    local repo_path="$1"
    local entry_file="$2"
    local min_count="${3:-2}"
    local max_count="${4:-5}"

    local count
    count=$(_entry_count "$entry_file")
    if [ "$count" -ge "$min_count" ]; then
        return 0
    fi

    # Add the main fallback entry (if any) first.
    local fallback
    fallback=$(_fallback_entry_point "$repo_path")
    _append_unique_entry "$entry_file" "$fallback" "$max_count"

    # Prefer siblings from directories that already contain selected entry points.
    local dirs_file
    dirs_file="$(dirname "$entry_file")/_entry_dirs.txt"
    : > "$dirs_file"
    while IFS= read -r existing_entry; do
        [ -z "$existing_entry" ] && continue
        dirname "$existing_entry" >> "$dirs_file"
    done < "$entry_file"
    sort -u "$dirs_file" -o "$dirs_file" 2>/dev/null || true

    while IFS= read -r dirpath; do
        [ -z "$dirpath" ] && continue
        find "$dirpath" -maxdepth 1 -type f \
            \( -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.json' \) \
            2>/dev/null | while IFS= read -r candidate; do
            _append_unique_entry "$entry_file" "$candidate" "$max_count"
            count=$(_entry_count "$entry_file")
            if [ "$count" -ge "$min_count" ] || [ "$count" -ge "$max_count" ]; then
                break
            fi
        done

        count=$(_entry_count "$entry_file")
        if [ "$count" -ge "$min_count" ] || [ "$count" -ge "$max_count" ]; then
            break
        fi
    done < "$dirs_file"

    # Then add broader repo candidates only if still below min_count.
    count=$(_entry_count "$entry_file")
    if [ "$count" -lt "$min_count" ]; then
        find "$repo_path" \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            -not -path '*/dist/*' \
            -not -path '*/build/*' \
            -type f \
            \( -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.json' \) \
            2>/dev/null | while IFS= read -r candidate; do
            _append_unique_entry "$entry_file" "$candidate" "$max_count"
            count=$(_entry_count "$entry_file")
            if [ "$count" -ge "$min_count" ] || [ "$count" -ge "$max_count" ]; then
                break
            fi
        done
    fi

    count=$(_entry_count "$entry_file")
    if [ "$count" -lt "$min_count" ]; then
        log_warn "Only $count entry point(s) available after fallback supplementation"
    fi
}

# Detect entry points for a query in a repository
# Args: query_text repo_path tmp_dir
# Output: Writes file paths to $tmp_dir/entry_points.txt
detect_entry_points() {
    local query_text="$1"
    local repo_path="$2"
    local tmp_dir="$3"

    local keywords_file="$tmp_dir/_keywords.txt"
    local scores_file="$tmp_dir/_scores.txt"
    local entry_file="$tmp_dir/entry_points.txt"

    # Extract keywords
    _extract_keywords "$query_text" > "$keywords_file"
    : > "$entry_file"

    if [ ! -s "$keywords_file" ]; then
        log_warn "No keywords extracted from query, using fallback"
        _append_unique_entry "$entry_file" "$(_fallback_entry_point "$repo_path")" 5
        _ensure_min_entry_points "$repo_path" "$entry_file" 2 5
        return 0
    fi

    # Initialize scores file
    : > "$scores_file"

    local keyword
    while IFS= read -r keyword; do
        [ -z "$keyword" ] && continue

        # Filename match: find files whose basename contains the keyword
        # Use -iname for case-insensitive matching
        # Search only JS/TS/JSON files, skip node_modules/dist/build/.git
        find "$repo_path" \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            -not -path '*/dist/*' \
            -not -path '*/build/*' \
            -type f \
            \( -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.json' \) \
            -iname "*${keyword}*" 2>/dev/null | while IFS= read -r filepath; do
            echo "3|${filepath}"
        done >> "$scores_file"

        # Directory match: files in directories whose name contains the keyword
        find "$repo_path" \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            -not -path '*/dist/*' \
            -not -path '*/build/*' \
            -type d \
            -iname "*${keyword}*" 2>/dev/null | while IFS= read -r dirpath; do
            find "$dirpath" -maxdepth 1 -type f \
                \( -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.json' \) \
                2>/dev/null | while IFS= read -r filepath; do
                echo "2|${filepath}"
            done
        done >> "$scores_file"

    done < "$keywords_file"

    if [ ! -s "$scores_file" ]; then
        log_warn "No matching files found for query keywords, using fallback"
        _append_unique_entry "$entry_file" "$(_fallback_entry_point "$repo_path")" 5
        _ensure_min_entry_points "$repo_path" "$entry_file" 2 5
        return 0
    fi

    # Aggregate scores per file: sum the score column grouped by file path
    # Format: score|filepath -> sum scores per filepath, sort desc
    local aggregated_file="$tmp_dir/_aggregated.txt"
    # Use awk to sum scores per file path
    awk -F'|' '{ scores[$2] += $1 } END { for (f in scores) print scores[f] "|" f }' \
        "$scores_file" | sort -t'|' -k1 -rn > "$aggregated_file"

    # Take top 2-5 files
    # Always include at least 2, up to 5 if score > 1
    local count=0
    local min_score=2
    while IFS='|' read -r score filepath; do
        if [ $count -ge 5 ]; then
            break
        fi
        if [ $count -ge 2 ] && [ "$score" -lt "$min_score" ]; then
            break
        fi
        echo "$filepath" >> "$entry_file"
        count=$((count + 1))
    done < "$aggregated_file"

    _ensure_min_entry_points "$repo_path" "$entry_file" 2 5

    local final_count
    final_count=$(wc -l < "$entry_file" | tr -d ' ')
    log_info "Detected $final_count entry points from query keywords" >&2
}

# Fallback: use repo's main entry point
# Args: repo_path
# Outputs: absolute file path to stdout
_fallback_entry_point() {
    local repo_path="$1"

    # Try package.json main field
    if [ -f "$repo_path/package.json" ]; then
        local main_field
        main_field=$(jq -r '.main // empty' "$repo_path/package.json" 2>/dev/null)
        if [ -n "$main_field" ] && [ -f "$repo_path/$main_field" ]; then
            echo "$repo_path/$main_field"
            return 0
        fi
    fi

    # Try index.js
    if [ -f "$repo_path/index.js" ]; then
        echo "$repo_path/index.js"
        return 0
    fi

    # Try src/index.js
    if [ -f "$repo_path/src/index.js" ]; then
        echo "$repo_path/src/index.js"
        return 0
    fi

    log_warn "No fallback entry point found"
    return 0
}
