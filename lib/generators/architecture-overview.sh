#!/usr/bin/env bash
# Generator: docs/architecture/overview.md
# Bash 3.2 compatible

generate_architecture_overview() {
    local tmp_dir="$1"
    local output_dir="$2"
    local sha="$3"
    local timestamp="$4"
    local output_file="$output_dir/docs/architecture/overview.md"

    log_info "Generating architecture overview..."
    ensure_dir "$(dirname "$output_file")"

    local structure_json="$tmp_dir/structure.json"
    local deps_json="$tmp_dir/dependencies.json"
    local patterns_json="$tmp_dir/patterns.json"
    local git_json="$tmp_dir/git-insights.json"

    # Header
    local header
    header=$(write_generated_header \
        "Architecture Overview" \
        "High-level architecture documentation for AI agent onboarding" \
        "AI agents and developers" \
        "$sha" "$timestamp")

    # Repo description
    local description
    description=$(jq -r '.description // "No description available"' "$structure_json")
    local repo_name
    repo_name=$(jq -r '.root' "$structure_json")

    # Structure type
    local is_monorepo
    is_monorepo=$(jq -r '.is_monorepo' "$structure_json")
    local total_files
    total_files=$(jq -r '.total_files' "$structure_json")
    local structure_type=""
    if [ "$is_monorepo" = "true" ]; then
        structure_type="This is a **monorepo** containing multiple packages/projects ($total_files total files)."
    else
        structure_type="This is a **single-project repository** ($total_files total files)."
    fi

    # Package table
    local package_table=""
    local pkg_count
    pkg_count=$(jq '.sub_packages | length' "$structure_json")
    if [ "$pkg_count" -gt 0 ]; then
        package_table="| Package | Path | Language | Files | Description |
|---------|------|----------|-------|-------------|
"
        local i=0
        while [ "$i" -lt "$pkg_count" ]; do
            local p_name p_path p_lang p_files p_desc
            p_name=$(jq -r ".sub_packages[$i].name" "$structure_json")
            p_path=$(jq -r ".sub_packages[$i].path" "$structure_json")
            p_lang=$(jq -r ".sub_packages[$i].primary_language" "$structure_json")
            p_files=$(jq -r ".sub_packages[$i].file_count" "$structure_json")
            p_desc=$(jq -r ".sub_packages[$i].description" "$structure_json")
            [ "$p_desc" = "null" ] || [ -z "$p_desc" ] && p_desc="-"
            package_table="${package_table}| $p_name | \`$p_path\` | $p_lang | $p_files | $p_desc |
"
            i=$((i + 1))
        done
    else
        # Show top-level directories instead
        package_table="| Directory | Files |
|-----------|-------|
"
        local dir_count
        dir_count=$(jq '.top_dirs | length' "$structure_json")
        local i=0
        while [ "$i" -lt "$dir_count" ]; do
            local d_name d_files
            d_name=$(jq -r ".top_dirs[$i].name" "$structure_json")
            d_files=$(jq -r ".top_dirs[$i].file_count" "$structure_json")
            package_table="${package_table}| \`$d_name/\` | $d_files |
"
            i=$((i + 1))
        done
    fi

    # Component details (per-package)
    local component_details=""
    if [ "$pkg_count" -gt 0 ]; then
        local i=0
        while [ "$i" -lt "$pkg_count" ]; do
            local p_name p_path p_lang p_desc p_entry
            p_name=$(jq -r ".sub_packages[$i].name" "$structure_json")
            p_path=$(jq -r ".sub_packages[$i].path" "$structure_json")
            p_lang=$(jq -r ".sub_packages[$i].primary_language" "$structure_json")
            p_desc=$(jq -r ".sub_packages[$i].description" "$structure_json")
            p_entry=$(jq -r ".sub_packages[$i].entry_points" "$structure_json")
            [ "$p_desc" = "null" ] || [ -z "$p_desc" ] && p_desc="No description available"
            [ "$p_entry" = "null" ] || [ -z "$p_entry" ] && p_entry="Not detected"

            component_details="${component_details}### $p_name (\`$p_path\`)

$p_desc

- **Primary Language**: $p_lang
- **Entry Points**: $p_entry

"
            i=$((i + 1))
        done
    else
        component_details="This repository does not appear to be a monorepo. See the Directory Map for structural details.
"
    fi

    # Dependency graph (text)
    local dep_graph=""
    if [ -f "$deps_json" ]; then
        local int_dep_count
        int_dep_count=$(jq '.internal_deps | length' "$deps_json")
        if [ "$int_dep_count" -gt 0 ]; then
            dep_graph="Internal package dependencies:

\`\`\`
"
            local i=0
            while [ "$i" -lt "$int_dep_count" ]; do
                local from to
                from=$(jq -r ".internal_deps[$i].from" "$deps_json")
                to=$(jq -r ".internal_deps[$i].to" "$deps_json")
                dep_graph="${dep_graph}  $from --> $to
"
                i=$((i + 1))
            done
            dep_graph="${dep_graph}\`\`\`"
        else
            dep_graph="No internal cross-package dependencies detected."
        fi
    else
        dep_graph="Dependency analysis not available."
    fi

    # Patterns summary
    local patterns_summary=""
    if [ -f "$patterns_json" ]; then
        local arch_pattern api_style config_approach
        arch_pattern=$(jq -r '.arch_pattern' "$patterns_json")
        api_style=$(jq -r '.api_style' "$patterns_json")
        config_approach=$(jq -r '.config_approach' "$patterns_json")

        patterns_summary="- **Architecture Pattern**: $arch_pattern
- **API Style**: $api_style
- **Configuration**: $config_approach
"
        local pattern_count
        pattern_count=$(jq '.detected_patterns | length' "$patterns_json")
        if [ "$pattern_count" -gt 0 ]; then
            patterns_summary="${patterns_summary}
Detected structural patterns:
"
            local i=0
            while [ "$i" -lt "$pattern_count" ]; do
                local pat_name pat_loc
                pat_name=$(jq -r ".detected_patterns[$i].name" "$patterns_json")
                pat_loc=$(jq -r ".detected_patterns[$i].location" "$patterns_json")
                patterns_summary="${patterns_summary}- **$pat_name** ($pat_loc)
"
                i=$((i + 1))
            done
        fi
    fi

    # Git activity
    local git_activity=""
    if [ -f "$git_json" ]; then
        local commits contributors
        commits=$(jq -r '.total_commits' "$git_json")
        contributors=$(jq -r '.contributors' "$git_json")
        git_activity="- **Total Commits**: $commits
- **Contributors**: $contributors
"
        local focus_count
        focus_count=$(jq '.recent_focus_areas | length' "$git_json")
        if [ "$focus_count" -gt 0 ]; then
            git_activity="${git_activity}
**Recent focus areas** (last 3 months):
"
            local i=0
            local max=5
            [ "$focus_count" -lt "$max" ] && max="$focus_count"
            while [ "$i" -lt "$max" ]; do
                local f_dir f_changes
                f_dir=$(jq -r ".recent_focus_areas[$i].directory" "$git_json")
                f_changes=$(jq -r ".recent_focus_areas[$i].changes" "$git_json")
                git_activity="${git_activity}- \`$f_dir\` ($f_changes changes)
"
                i=$((i + 1))
            done
        fi
    else
        git_activity="Git history analysis not available."
    fi

    # Assemble the document
    cat > "$output_file" <<OVERVIEW
${header}

# Architecture Overview

${description}

## Repository Structure

${structure_type}

${package_table}

## Component Details

${component_details}

## Component Relationships

${dep_graph}

## Key Patterns

${patterns_summary}

## Active Development Areas

${git_activity}
OVERVIEW

    log_success "Generated $(basename "$output_file")"
}
