#!/usr/bin/env bash
# Analyzer: Inter-package dependency analysis
# Outputs: dependencies.json to TMPDIR
# Bash 3.2 compatible

analyze_dependencies() {
    local repo_path="$1"
    local tmp_dir="$2"
    local output_file="$tmp_dir/dependencies.json"

    log_info "Analyzing dependencies..."

    local internal_deps_json="[]"
    local shared_packages_json="[]"
    local external_dep_count=0

    # Collect all package names in the repo
    local pkg_names_file="$tmp_dir/_pkg_names.txt"
    find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name 'package.json' -maxdepth 3 2>/dev/null \
        | while IFS= read -r pjson; do
            jq -r '.name // empty' "$pjson" 2>/dev/null
        done | sort -u > "$pkg_names_file"

    # For each package.json, check if any dependency references another internal package
    # Write internal deps to file directly (not via pipe) to avoid subshell variable loss
    > "$tmp_dir/_internal_deps_raw.txt"
    while IFS= read -r pjson; do
        [ -z "$pjson" ] && continue
        local src_name
        src_name=$(jq -r '.name // empty' "$pjson" 2>/dev/null)
        [ -z "$src_name" ] && continue

        local src_dir
        src_dir=$(dirname "$pjson")
        local src_rel
        src_rel="${src_dir#$repo_path/}"

        # Count external deps
        local ext_count
        ext_count=$(jq -r '(.dependencies // {} | keys | length) + (.devDependencies // {} | keys | length)' "$pjson" 2>/dev/null)
        if [ -n "$ext_count" ] && [ "$ext_count" -gt 0 ] 2>/dev/null; then
            external_dep_count=$((external_dep_count + ext_count))
        fi

        # Check each dep against internal package names
        local all_deps
        all_deps=$(jq -r '(.dependencies // {} | keys[]), (.devDependencies // {} | keys[])' "$pjson" 2>/dev/null)
        echo "$all_deps" | while IFS= read -r dep; do
            [ -z "$dep" ] && continue
            if grep -q "^$dep$" "$pkg_names_file" 2>/dev/null; then
                if [ "$dep" != "$src_name" ]; then
                    echo "$src_name|$dep"
                fi
            fi
        done >> "$tmp_dir/_internal_deps_raw.txt"
    done < <(find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name 'package.json' -maxdepth 3 2>/dev/null)
    sort -u "$tmp_dir/_internal_deps_raw.txt" > "$tmp_dir/_internal_deps.txt"

    # Build internal deps JSON using jq for safe escaping
    internal_deps_json="[]"
    while IFS='|' read -r from to; do
        [ -z "$from" ] && continue
        internal_deps_json=$(echo "$internal_deps_json" | jq --arg f "$from" --arg t "$to" '. + [{"from": $f, "to": $t}]')
    done < "$tmp_dir/_internal_deps.txt"

    # Detect shared/common packages
    shared_packages_json="[]"
    for shared_dir in "common" "shared" "lib" "packages" "libs" "utils"; do
        if [ -d "$repo_path/$shared_dir" ]; then
            local s_count
            s_count=$(find "$repo_path/$shared_dir" -not -path '*/.git/*' -not -path '*/node_modules/*' -type f 2>/dev/null | wc -l | tr -d ' ')
            shared_packages_json=$(echo "$shared_packages_json" | jq --arg n "$shared_dir" --argjson c "$s_count" '. + [{"name": $n, "file_count": $c}]')
        fi
    done

    # Top external dependencies across all package.json files
    find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name 'package.json' -maxdepth 3 2>/dev/null \
        | while IFS= read -r pjson; do
            jq -r '.dependencies // {} | keys[]' "$pjson" 2>/dev/null
        done | sort | uniq -c | sort -rn | head -10 | while read -r count dep; do
            echo "$count|$dep"
        done > "$tmp_dir/_top_deps.txt"

    local top_deps_json="[]"
    while IFS='|' read -r count dep; do
        [ -z "$dep" ] && continue
        top_deps_json=$(echo "$top_deps_json" | jq --arg n "$dep" --argjson c "$count" '. + [{"name": $n, "used_by_count": $c}]')
    done < "$tmp_dir/_top_deps.txt"

    jq -n \
        --argjson internal_deps "$internal_deps_json" \
        --argjson shared_packages "$shared_packages_json" \
        --argjson top_external "$top_deps_json" \
        --argjson external_dep_count "$external_dep_count" \
        '{
            internal_deps: $internal_deps,
            shared_packages: $shared_packages,
            top_external_deps: $top_external,
            external_dep_count: $external_dep_count
        }' > "$output_file"

    log_success "Dependency analysis complete"
}
