#!/usr/bin/env bash
# Generator: docs/architecture/tech-stack.md
# Bash 3.2 compatible

generate_tech_stack_doc() {
    local tmp_dir="$1"
    local output_dir="$2"
    local sha="$3"
    local timestamp="$4"
    local output_file="$output_dir/docs/architecture/tech-stack.md"

    log_info "Generating tech stack documentation..."
    ensure_dir "$(dirname "$output_file")"

    local ts_json="$tmp_dir/tech-stack.json"
    local header
    header=$(write_generated_header \
        "Technology Stack" \
        "Languages, frameworks, databases, and tools used in this repository" \
        "AI agents and developers" \
        "$sha" "$timestamp")

    # Languages table
    local languages_table="| Language | Extension | Files |
|----------|-----------|-------|
"
    local total_source_files=0
    local lang_count
    lang_count=$(jq '.languages | length' "$ts_json")
    local i=0
    while [ "$i" -lt "$lang_count" ]; do
        local l_name l_ext l_count
        l_name=$(jq -r ".languages[$i].name" "$ts_json")
        l_ext=$(jq -r ".languages[$i].extension" "$ts_json")
        l_count=$(jq -r ".languages[$i].file_count" "$ts_json")
        # Skip non-source-code types for the main table
        case "$l_name" in
            Markdown|JSON|YAML|CSS|HTML) ;;
            *)
                total_source_files=$((total_source_files + l_count))
                ;;
        esac
        languages_table="${languages_table}| $l_name | .$l_ext | $l_count |
"
        i=$((i + 1))
    done

    # Frameworks table
    local frameworks_table=""
    local fw_count
    fw_count=$(jq '.frameworks | length' "$ts_json")
    if [ "$fw_count" -gt 0 ]; then
        frameworks_table="| Framework | Category | Role |
|-----------|----------|------|
"
        i=0
        while [ "$i" -lt "$fw_count" ]; do
            local f_name f_cat f_role
            f_name=$(jq -r ".frameworks[$i].name" "$ts_json")
            f_cat=$(jq -r ".frameworks[$i].category" "$ts_json")
            f_role=$(jq -r ".frameworks[$i].role" "$ts_json")
            frameworks_table="${frameworks_table}| $f_name | $f_cat | $f_role |
"
            i=$((i + 1))
        done
    else
        frameworks_table="No frameworks detected."
    fi

    # Datastores table
    local datastores_table=""
    local ds_count
    ds_count=$(jq '.datastores | length' "$ts_json")
    if [ "$ds_count" -gt 0 ]; then
        datastores_table="| Data Store | Driver/Client |
|-----------|---------------|
"
        i=0
        while [ "$i" -lt "$ds_count" ]; do
            local d_name d_driver
            d_name=$(jq -r ".datastores[$i].name" "$ts_json")
            d_driver=$(jq -r ".datastores[$i].driver" "$ts_json")
            datastores_table="${datastores_table}| $d_name | $d_driver |
"
            i=$((i + 1))
        done
    else
        datastores_table="No data stores detected."
    fi

    # Build tools table
    local build_tools_table=""
    local bt_count
    bt_count=$(jq '.build_tools | length' "$ts_json")
    if [ "$bt_count" -gt 0 ]; then
        build_tools_table="| Tool | Role |
|------|------|
"
        i=0
        while [ "$i" -lt "$bt_count" ]; do
            local b_name b_role
            b_name=$(jq -r ".build_tools[$i].name" "$ts_json")
            b_role=$(jq -r ".build_tools[$i].role" "$ts_json")
            build_tools_table="${build_tools_table}| $b_name | $b_role |
"
            i=$((i + 1))
        done
    else
        build_tools_table="No build tools detected."
    fi

    # Test tools table
    local test_tools_table=""
    local tt_count
    tt_count=$(jq '.test_tools | length' "$ts_json")
    if [ "$tt_count" -gt 0 ]; then
        test_tools_table="| Tool | Role |
|------|------|
"
        i=0
        while [ "$i" -lt "$tt_count" ]; do
            local t_name t_role
            t_name=$(jq -r ".test_tools[$i].name" "$ts_json")
            t_role=$(jq -r ".test_tools[$i].role" "$ts_json")
            test_tools_table="${test_tools_table}| $t_name | $t_role |
"
            i=$((i + 1))
        done
    else
        test_tools_table="No test tools detected."
    fi

    # Notable dependencies
    local notable_deps=""
    local deps_json="$tmp_dir/dependencies.json"
    if [ -f "$deps_json" ]; then
        local ext_count
        ext_count=$(jq -r '.external_dep_count' "$deps_json")
        notable_deps="Total external dependencies across all packages: **$ext_count**
"
        local top_count
        top_count=$(jq '.top_external_deps | length' "$deps_json")
        if [ "$top_count" -gt 0 ]; then
            notable_deps="${notable_deps}
Most commonly used dependencies:
"
            i=0
            while [ "$i" -lt "$top_count" ]; do
                local td_name td_used
                td_name=$(jq -r ".top_external_deps[$i].name" "$deps_json")
                td_used=$(jq -r ".top_external_deps[$i].used_by_count" "$deps_json")
                notable_deps="${notable_deps}- \`$td_name\` (used by $td_used packages)
"
                i=$((i + 1))
            done
        fi
    fi

    # Cross-references
    local cross_refs
    cross_refs=$(write_cross_references "docs/architecture/tech-stack.md")

    cat > "$output_file" <<TECHSTACK
${header}

# Technology Stack

## Languages

${languages_table}

## Frameworks & Libraries

${frameworks_table}

## Data Stores

${datastores_table}

## Build & Dev Tools

${build_tools_table}

## Test Tools

${test_tools_table}

## Notable Dependencies

${notable_deps}
${cross_refs}
TECHSTACK

    log_success "Generated $(basename "$output_file")"
}
