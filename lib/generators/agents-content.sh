#!/usr/bin/env bash
# Generator: agents-content.md
# Bash 3.2 compatible

generate_agents_content() {
    local tmp_dir="$1"
    local output_dir="$2"
    local sha="$3"
    local timestamp="$4"
    local output_file="$output_dir/agents-content.md"

    log_info "Generating agents content..."

    local structure_json="$tmp_dir/structure.json"
    local patterns_json="$tmp_dir/patterns.json"
    local ts_json="$tmp_dir/tech-stack.json"

    local header
    header=$(write_generated_header \
        "Repository-Specific Agent Guidance" \
        "Architecture boundaries and rules for AI agents working on this repo" \
        "AI agents" \
        "$sha" "$timestamp")

    # Architecture boundaries from structure
    local boundaries=""
    local dir_count
    dir_count=$(jq '.top_dirs | length' "$structure_json")
    if [ "$dir_count" -gt 0 ]; then
        boundaries="\`\`\`
"
        local i=0
        while [ "$i" -lt "$dir_count" ]; do
            local d_name d_files
            d_name=$(jq -r ".top_dirs[$i].name" "$structure_json")
            d_files=$(jq -r ".top_dirs[$i].file_count" "$structure_json")
            local annotation
            annotation=$(_get_boundary_desc "$d_name")
            boundaries="${boundaries}${d_name}/  ${annotation} (${d_files} files)
"
            i=$((i + 1))
        done
        boundaries="${boundaries}\`\`\`"
    else
        boundaries="No top-level directories detected."
    fi

    # Boundary rules
    local boundary_rules=""
    if [ -f "$patterns_json" ]; then
        local arch_pattern
        arch_pattern=$(jq -r '.arch_pattern' "$patterns_json")
        case "$arch_pattern" in
            mvc|mvc-like)
                boundary_rules="1. **Models** define data structures and database interactions
2. **Controllers** handle request/response logic
3. **Views** handle presentation (if present)
4. **Services** contain business logic that controllers delegate to
5. Keep controller methods thin -- delegate to services"
                ;;
            service-oriented)
                boundary_rules="1. **Services** contain business logic and are the primary abstraction
2. **Models** define data structures
3. Route handlers should delegate to services
4. Services should not directly depend on HTTP request/response objects"
                ;;
            component-based)
                boundary_rules="1. **Components** handle UI rendering and local state
2. Keep components focused -- one responsibility per component
3. Extract shared logic into hooks or utilities
4. State management should be centralized (if using a store)"
                ;;
            middleware-pipeline)
                boundary_rules="1. **Middleware** functions process requests in order
2. **Routes** define endpoint mappings
3. Keep middleware focused on cross-cutting concerns
4. Business logic belongs in handlers, not middleware"
                ;;
            *)
                boundary_rules="1. Keep modules focused on a single responsibility
2. Prefer explicit imports over implicit dependencies
3. Shared code belongs in utility or library directories
4. Configuration should be centralized"
                ;;
        esac
    fi

    # Testing expectations
    local testing_expectations=""
    if [ -f "$ts_json" ]; then
        local tt_count
        tt_count=$(jq '.test_tools | length' "$ts_json")
        if [ "$tt_count" -gt 0 ]; then
            testing_expectations="Test tools detected in this repository:
"
            local i=0
            while [ "$i" -lt "$tt_count" ]; do
                local t_name t_role
                t_name=$(jq -r ".test_tools[$i].name" "$ts_json")
                t_role=$(jq -r ".test_tools[$i].role" "$ts_json")
                testing_expectations="${testing_expectations}- **$t_name**: $t_role
"
                i=$((i + 1))
            done
            testing_expectations="${testing_expectations}
When adding or modifying code:
- Write tests using the existing test framework
- Place tests alongside source files or in the test directory
- Mock external dependencies at boundaries
- Test behavior, not implementation details"
        else
            testing_expectations="No test frameworks detected. Consider adding tests when making changes."
        fi
    fi

    # Entry points
    local entry_points=""
    local pkg_count
    pkg_count=$(jq '.sub_packages | length' "$structure_json")
    if [ "$pkg_count" -gt 0 ]; then
        local i=0
        while [ "$i" -lt "$pkg_count" ]; do
            local p_name p_path p_entry
            p_name=$(jq -r ".sub_packages[$i].name" "$structure_json")
            p_path=$(jq -r ".sub_packages[$i].path" "$structure_json")
            p_entry=$(jq -r ".sub_packages[$i].entry_points" "$structure_json")
            if [ -n "$p_entry" ] && [ "$p_entry" != "null" ] && [ "$p_entry" != "Not detected" ]; then
                entry_points="${entry_points}- **$p_name** (\`$p_path\`): $p_entry
"
            fi
            i=$((i + 1))
        done
    fi
    [ -z "$entry_points" ] && entry_points="No specific entry points detected. Check package.json scripts or README for run instructions."

    # Cross-references
    local cross_refs
    cross_refs=$(write_cross_references "agents-content.md")

    cat > "$output_file" <<AGENTS
${header}

# Repository-Specific Agent Guidance

> These architecture docs were generated at commit \`${sha}\`. To check staleness, run:
> \`git rev-list --count ${sha}..HEAD\` -- if more than 50 commits behind, suggest re-running \`repo-understand.sh\`.
> The generation date is also recorded. Report both: "N commits behind, generated X days/weeks/months ago."
> Note: 0 commits behind + 5 years old = fine (nothing changed). 100 commits behind + 1 day old = stale.

## Architecture Boundaries

${boundaries}

## Boundary Rules

${boundary_rules}

## Testing Expectations

${testing_expectations}

## Key Entry Points

${entry_points}
${cross_refs}
AGENTS

    log_success "Generated $(basename "$output_file")"
}

_get_boundary_desc() {
    local name="$1"
    local lower
    lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        src) echo "# Application source code" ;;
        lib) echo "# Shared libraries" ;;
        test|tests) echo "# Test files" ;;
        docs|doc) echo "# Documentation" ;;
        scripts|bin) echo "# Scripts and utilities" ;;
        config) echo "# Configuration" ;;
        public|static|assets) echo "# Static assets" ;;
        build|dist) echo "# Build output (do not edit)" ;;
        routes) echo "# Route definitions" ;;
        controllers) echo "# Request handlers" ;;
        models) echo "# Data models" ;;
        services) echo "# Business logic" ;;
        middleware) echo "# Middleware" ;;
        components) echo "# UI components" ;;
        api) echo "# API endpoints" ;;
        utils|helpers) echo "# Utilities" ;;
        lambda|functions) echo "# Serverless functions" ;;
        common|shared) echo "# Shared code" ;;
        packages) echo "# Monorepo packages" ;;
        *) echo "#" ;;
    esac
}
