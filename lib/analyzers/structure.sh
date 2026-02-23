#!/usr/bin/env bash
# Analyzer: Directory and file structure analysis
# Outputs: structure.json to TMPDIR
# Bash 3.2 compatible

analyze_structure() {
    local repo_path="$1"
    local tmp_dir="$2"
    local output_file="$tmp_dir/structure.json"

    log_info "Analyzing directory structure..."

    local total_files
    total_files=$(count_files "$repo_path")

    # File counts by extension (top 15)
    local ext_counts_file="$tmp_dir/_ext_counts.txt"
    find "$repo_path" -not -path '*/.git/*' -type f -name '*.*' 2>/dev/null \
        | sed 's/.*\.//' \
        | tr '[:upper:]' '[:lower:]' \
        | sort | uniq -c | sort -rn | head -15 \
        > "$ext_counts_file"

    # Build file_counts JSON array using jq for safe escaping
    local file_counts_json="[]"
    while read -r count ext; do
        file_counts_json=$(echo "$file_counts_json" | jq --arg e "$ext" --argjson c "$count" '. + [{"extension": $e, "count": $c}]')
    done < "$ext_counts_file"

    # Detect monorepo indicators
    local package_json_count
    package_json_count=$(find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name 'package.json' -maxdepth 3 2>/dev/null | wc -l | tr -d ' ')

    local go_mod_count
    go_mod_count=$(find "$repo_path" -not -path '*/.git/*' -name 'go.mod' -maxdepth 3 2>/dev/null | wc -l | tr -d ' ')

    local cargo_toml_count
    cargo_toml_count=$(find "$repo_path" -not -path '*/.git/*' -name 'Cargo.toml' -maxdepth 3 2>/dev/null | wc -l | tr -d ' ')

    local is_monorepo="false"
    if [ "$package_json_count" -gt 2 ] || [ "$go_mod_count" -gt 1 ] || [ "$cargo_toml_count" -gt 1 ]; then
        is_monorepo="true"
    fi

    # Detect sub-packages (directories with their own package.json, go.mod, etc.)
    local sub_packages_json="[]"
    local pkg_file

    # Look for package.json at depth 1-2 (not root)
    while IFS= read -r pkg_file; do
        [ -z "$pkg_file" ] && continue
        local pkg_dir
        pkg_dir=$(dirname "$pkg_file")
        local pkg_rel
        pkg_rel="${pkg_dir#$repo_path/}"
        [ "$pkg_rel" = "$repo_path" ] && continue
        [ "$pkg_rel" = "." ] && continue

        local pkg_name=""
        local pkg_desc=""
        if [ -f "$pkg_file" ]; then
            pkg_name=$(jq -r '.name // empty' "$pkg_file" 2>/dev/null)
            pkg_desc=$(jq -r '.description // empty' "$pkg_file" 2>/dev/null)
        fi
        [ -z "$pkg_name" ] && pkg_name=$(basename "$pkg_dir")

        local pkg_file_count
        pkg_file_count=$(find "$pkg_dir" -not -path '*/.git/*' -not -path '*/node_modules/*' -type f 2>/dev/null | wc -l | tr -d ' ')

        # Detect primary language
        local primary_lang="unknown"
        local ts_count
        ts_count=$(find "$pkg_dir" -not -path '*/node_modules/*' -type f \( -name '*.ts' -o -name '*.tsx' \) 2>/dev/null | wc -l | tr -d ' ')
        local js_count
        js_count=$(find "$pkg_dir" -not -path '*/node_modules/*' -type f \( -name '*.js' -o -name '*.jsx' \) 2>/dev/null | wc -l | tr -d ' ')
        local coffee_count
        coffee_count=$(find "$pkg_dir" -not -path '*/node_modules/*' -type f -name '*.coffee' 2>/dev/null | wc -l | tr -d ' ')
        local py_count
        py_count=$(find "$pkg_dir" -not -path '*/node_modules/*' -type f -name '*.py' 2>/dev/null | wc -l | tr -d ' ')

        if [ "$ts_count" -gt "$js_count" ] && [ "$ts_count" -gt "$coffee_count" ] && [ "$ts_count" -gt "$py_count" ]; then
            primary_lang="TypeScript"
        elif [ "$js_count" -gt "$coffee_count" ] && [ "$js_count" -gt "$py_count" ]; then
            primary_lang="JavaScript"
        elif [ "$coffee_count" -gt "$py_count" ] && [ "$coffee_count" -gt 0 ]; then
            primary_lang="CoffeeScript"
        elif [ "$py_count" -gt 0 ]; then
            primary_lang="Python"
        fi

        # Detect entry points
        local entry_points=""
        for ep_candidate in "index.js" "index.ts" "main.js" "main.ts" "server.js" "server.ts" "app.js" "app.ts" "src/index.ts" "src/index.js" "src/main.ts" "src/main.js"; do
            if [ -f "$pkg_dir/$ep_candidate" ]; then
                if [ -n "$entry_points" ]; then
                    entry_points="$entry_points, $ep_candidate"
                else
                    entry_points="$ep_candidate"
                fi
            fi
        done
        # Also check package.json main field
        if [ -f "$pkg_file" ]; then
            local pkg_main
            pkg_main=$(jq -r '.main // empty' "$pkg_file" 2>/dev/null)
            if [ -n "$pkg_main" ] && [ -f "$pkg_dir/$pkg_main" ]; then
                if [ -n "$entry_points" ]; then
                    entry_points="$entry_points, $pkg_main (main)"
                else
                    entry_points="$pkg_main (main)"
                fi
            fi
        fi

        sub_packages_json=$(echo "$sub_packages_json" | jq \
            --arg name "$pkg_name" \
            --arg path "$pkg_rel" \
            --arg desc "$pkg_desc" \
            --arg lang "$primary_lang" \
            --argjson fc "$pkg_file_count" \
            --arg ep "$entry_points" \
            '. + [{"name": $name, "path": $path, "description": $desc, "primary_language": $lang, "file_count": $fc, "entry_points": $ep}]')
    done < <(find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name 'package.json' -maxdepth 3 2>/dev/null | sort)

    # Also look for go.mod and Cargo.toml sub-packages
    for marker in "go.mod" "Cargo.toml" "setup.py" "pyproject.toml"; do
        while IFS= read -r marker_file; do
            [ -z "$marker_file" ] && continue
            local m_dir
            m_dir=$(dirname "$marker_file")
            local m_rel
            m_rel="${m_dir#$repo_path/}"
            [ "$m_rel" = "$repo_path" ] && continue
            [ "$m_rel" = "." ] && continue

            local m_name
            m_name=$(basename "$m_dir")
            local m_file_count
            m_file_count=$(find "$m_dir" -not -path '*/.git/*' -type f 2>/dev/null | wc -l | tr -d ' ')

            sub_packages_json=$(echo "$sub_packages_json" | jq \
                --arg name "$m_name" \
                --arg path "$m_rel" \
                --argjson fc "$m_file_count" \
                '. + [{"name": $name, "path": $path, "description": "", "primary_language": "unknown", "file_count": $fc, "entry_points": ""}]')
        done < <(find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name "$marker" -maxdepth 3 -not -path "$repo_path/$marker" 2>/dev/null | sort)
    done

    # Top-level directories with file counts
    local top_dirs_json="[]"
    for d in "$repo_path"/*/; do
        [ ! -d "$d" ] && continue
        local dname
        dname=$(basename "$d")
        # Skip hidden dirs and node_modules
        case "$dname" in
            .*|node_modules) continue ;;
        esac
        local d_count
        d_count=$(find "$d" -not -path '*/.git/*' -not -path '*/node_modules/*' -type f 2>/dev/null | wc -l | tr -d ' ')
        top_dirs_json=$(echo "$top_dirs_json" | jq --arg n "$dname" --argjson c "$d_count" '. + [{"name": $n, "file_count": $c}]')
    done

    # Repo description from root README or package.json
    local repo_description=""
    if [ -f "$repo_path/package.json" ]; then
        repo_description=$(jq -r '.description // empty' "$repo_path/package.json" 2>/dev/null)
    fi
    if [ -z "$repo_description" ] && [ -f "$repo_path/README.md" ]; then
        # Extract first non-header, non-empty paragraph
        repo_description=$(sed -n '/^[^#\[]/{/^$/d; p; q;}' "$repo_path/README.md" 2>/dev/null)
    fi
    repo_description=$(echo "$repo_description" | head -1)

    # Get tree depth
    local tree_depth
    tree_depth=$(find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -type d 2>/dev/null \
        | while IFS= read -r d; do echo "${d#$repo_path}"; done | awk -F/ '{print NF}' | sort -n | tail -1)
    [ -z "$tree_depth" ] && tree_depth=0

    # Write JSON output
    jq -n \
        --arg root "$(basename "$repo_path")" \
        --arg description "$repo_description" \
        --argjson total_files "$total_files" \
        --argjson tree_depth "$tree_depth" \
        --argjson is_monorepo "$is_monorepo" \
        --argjson file_counts "$file_counts_json" \
        --argjson sub_packages "$sub_packages_json" \
        --argjson top_dirs "$top_dirs_json" \
        '{
            root: $root,
            description: $description,
            total_files: $total_files,
            tree_depth: $tree_depth,
            is_monorepo: $is_monorepo,
            file_counts: $file_counts,
            sub_packages: $sub_packages,
            top_dirs: $top_dirs
        }' > "$output_file"

    log_success "Structure analysis complete ($total_files files)"
}
