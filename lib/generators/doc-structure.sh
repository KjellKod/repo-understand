#!/usr/bin/env bash
# Generator: doc-structure.md
# Bash 3.2 compatible

generate_doc_structure() {
    local tmp_dir="$1"
    local output_dir="$2"
    local sha="$3"
    local timestamp="$4"
    local repo_path="$5"
    local output_file="$output_dir/doc-structure.md"

    log_info "Generating documentation structure..."

    local header
    header=$(write_generated_header \
        "Documentation Structure" \
        "Map of existing documentation and recommended navigation" \
        "AI agents and developers" \
        "$sha" "$timestamp")

    # Find existing documentation files
    local docs_found=""
    local doc_files_file="$tmp_dir/_doc_files.txt"
    find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' \
        -type f \( -name '*.md' -o -name '*.rst' -o -name '*.txt' -o -name '*.adoc' \) \
        -maxdepth 4 2>/dev/null \
        | while IFS= read -r f; do echo "${f#$repo_path/}"; done \
        | sort > "$doc_files_file"

    local doc_count
    doc_count=$(wc -l < "$doc_files_file" | tr -d ' ')

    if [ "$doc_count" -gt 0 ]; then
        docs_found="Found **${doc_count}** documentation files:

"
        # Group by top-level directory
        local current_group=""
        while IFS= read -r doc_file; do
            [ -z "$doc_file" ] && continue
            local group
            group=$(echo "$doc_file" | cut -d'/' -f1)
            if [ "$group" != "$current_group" ]; then
                current_group="$group"
                if echo "$doc_file" | grep -q '/'; then
                    docs_found="${docs_found}
**\`${group}/\`**:
"
                fi
            fi
            docs_found="${docs_found}- \`$doc_file\`
"
        done < "$doc_files_file"
    else
        docs_found="No documentation files found."
    fi

    # Build navigation table
    local nav_table=""

    # Principles layer
    local has_agents_md="false"
    local has_readme="false"
    [ -f "$repo_path/AGENTS.md" ] && has_agents_md="true"
    [ -f "$repo_path/README.md" ] && has_readme="true"

    if [ "$has_readme" = "true" ]; then
        nav_table="${nav_table}| Principles | \`README.md\` | Project overview and getting started |
"
    fi
    if [ "$has_agents_md" = "true" ]; then
        nav_table="${nav_table}| Principles | \`AGENTS.md\` | Coding rules and architecture boundaries |
"
    fi
    if [ -f "$repo_path/CONTRIBUTING.md" ]; then
        nav_table="${nav_table}| Principles | \`CONTRIBUTING.md\` | Contribution guidelines |
"
    fi
    if [ -f "$repo_path/CHANGELOG.md" ]; then
        nav_table="${nav_table}| Principles | \`CHANGELOG.md\` | Change history |
"
    fi

    # Architecture layer
    if [ -d "$repo_path/docs/architecture" ]; then
        while IFS= read -r arch_file; do
            [ -z "$arch_file" ] && continue
            local rel_path
            rel_path="${arch_file#$repo_path/}"
            local fname
            fname=$(basename "$arch_file" .md)
            nav_table="${nav_table}| Architecture | \`$rel_path\` | ${fname} documentation |
"
        done < <(find "$repo_path/docs/architecture" -name '*.md' -type f 2>/dev/null | sort)
    fi

    # Implementation layer
    if [ -d "$repo_path/docs/implementation" ]; then
        nav_table="${nav_table}| Implementation | \`docs/implementation/\` | Active implementation plans |
"
    fi

    # Guides layer
    if [ -d "$repo_path/docs/guides" ]; then
        while IFS= read -r guide_file; do
            [ -z "$guide_file" ] && continue
            local rel_path
            rel_path="${guide_file#$repo_path/}"
            local fname
            fname=$(basename "$guide_file" .md)
            nav_table="${nav_table}| Guides | \`$rel_path\` | ${fname} |
"
        done < <(find "$repo_path/docs/guides" -name '*.md' -type f 2>/dev/null | sort)
    fi

    # History layer
    if [ -d "$repo_path/docs/implementation/history" ]; then
        nav_table="${nav_table}| History | \`docs/implementation/history/\` | Past decisions and completed plans |
"
    fi

    # Skills
    if [ -d "$repo_path/.skills" ]; then
        nav_table="${nav_table}| Skills | \`.skills/\` | Specialized workflow instructions for AI agents |
"
    fi

    # If nav table is empty, provide a minimal one
    if [ -z "$nav_table" ]; then
        nav_table="| Principles | \`README.md\` | Project overview (if present) |
"
    fi

    # Documentation gaps
    local doc_gaps=""
    if [ "$has_readme" != "true" ]; then
        doc_gaps="${doc_gaps}- Missing \`README.md\` -- consider adding project overview
"
    fi
    if [ ! -d "$repo_path/docs/architecture" ]; then
        doc_gaps="${doc_gaps}- No \`docs/architecture/\` directory -- consider adding architecture documentation
"
    fi
    if [ ! -d "$repo_path/docs/guides" ]; then
        doc_gaps="${doc_gaps}- No \`docs/guides/\` directory -- consider adding how-to guides
"
    fi
    if [ "$has_agents_md" != "true" ]; then
        doc_gaps="${doc_gaps}- No \`AGENTS.md\` -- consider adding coding rules for AI agents
"
    fi
    [ -z "$doc_gaps" ] && doc_gaps="No significant documentation gaps detected."

    cat > "$output_file" <<DOCSTRUCT
${header}

# Documentation Structure

## Existing Documentation

The following documentation was discovered in this repository.

${docs_found}

## Navigation Table

| Layer | Location | Purpose |
|-------|----------|---------|
${nav_table}

## Documentation Gaps

${doc_gaps}
DOCSTRUCT

    log_success "Generated $(basename "$output_file")"
}
