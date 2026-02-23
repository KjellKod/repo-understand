#!/usr/bin/env bash
# Generator: docs/architecture/directory-map.md
# Bash 3.2 compatible

generate_directory_map() {
    local tmp_dir="$1"
    local output_dir="$2"
    local sha="$3"
    local timestamp="$4"
    local repo_path="$5"
    local output_file="$output_dir/docs/architecture/directory-map.md"

    log_info "Generating directory map..."
    ensure_dir "$(dirname "$output_file")"

    local header
    header=$(write_generated_header \
        "Directory Map" \
        "Annotated directory tree for navigation" \
        "AI agents and developers" \
        "$sha" "$timestamp")

    # Build annotated tree (top 2 levels)
    local tree_output=""
    local repo_name
    repo_name=$(basename "$repo_path")
    tree_output="${repo_name}/
"

    # Get top-level entries sorted
    local entries_file="$tmp_dir/_tree_entries.txt"
    ls -1 "$repo_path" 2>/dev/null | while IFS= read -r entry; do
        # Skip hidden files and node_modules
        case "$entry" in
            .*|node_modules) continue ;;
        esac
        if [ -d "$repo_path/$entry" ]; then
            echo "d|$entry"
        else
            echo "f|$entry"
        fi
    done | sort > "$entries_file"

    local details_output=""
    local entry_count
    entry_count=$(wc -l < "$entries_file" | tr -d ' ')
    local current=0

    while IFS='|' read -r etype ename; do
        current=$((current + 1))
        local connector
        if [ "$current" -eq "$entry_count" ]; then
            connector="└──"
            local sub_prefix="    "
        else
            connector="├──"
            local sub_prefix="│   "
        fi

        if [ "$etype" = "d" ]; then
            local annotation
            annotation=$(_annotate_dir "$ename")
            local d_files
            d_files=$(find "$repo_path/$ename" -not -path '*/.git/*' -not -path '*/node_modules/*' -type f 2>/dev/null | wc -l | tr -d ' ')
            tree_output="${tree_output}${connector} ${ename}/  ${annotation} (${d_files} files)
"

            # Level 2
            local sub_entries=""
            local sub_count=0
            for sub in "$repo_path/$ename"/*/; do
                [ ! -d "$sub" ] && continue
                local subname
                subname=$(basename "$sub")
                case "$subname" in
                    .git|node_modules|__pycache__|.*) continue ;;
                esac
                sub_count=$((sub_count + 1))
                [ "$sub_count" -gt 10 ] && break
                local sub_annotation
                sub_annotation=$(_annotate_dir "$subname")
                local sub_files
                sub_files=$(find "$sub" -not -path '*/.git/*' -not -path '*/node_modules/*' -type f 2>/dev/null | wc -l | tr -d ' ')
                sub_entries="${sub_entries}${sub_prefix}├── ${subname}/  ${sub_annotation} (${sub_files} files)
"
            done
            if [ "$sub_count" -gt 10 ]; then
                sub_entries="${sub_entries}${sub_prefix}└── ... (more subdirectories)
"
            fi
            tree_output="${tree_output}${sub_entries}"

            # Directory details section
            details_output="${details_output}### \`${ename}/\`

${annotation}

- **Files**: ${d_files}
"
            # List notable files
            local notable=""
            for nf in "README.md" "package.json" "tsconfig.json" "Makefile" "Dockerfile" "go.mod" "Cargo.toml" "setup.py" "pyproject.toml"; do
                if [ -f "$repo_path/$ename/$nf" ]; then
                    notable="${notable}- \`$nf\`
"
                fi
            done
            if [ -n "$notable" ]; then
                details_output="${details_output}- **Notable files**:
${notable}"
            fi
            details_output="${details_output}
"
        else
            tree_output="${tree_output}${connector} ${ename}
"
        fi
    done < "$entries_file"

    cat > "$output_file" <<DIRMAP
${header}

# Directory Map

Annotated directory tree for the top 2 levels of the repository.

\`\`\`
${tree_output}\`\`\`

## Directory Details

${details_output}
DIRMAP

    log_success "Generated $(basename "$output_file")"
}

# Annotate a directory based on its name
_annotate_dir() {
    local name="$1"
    local lower
    lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        src) echo "# Application source code" ;;
        lib) echo "# Shared libraries" ;;
        libs) echo "# Shared libraries" ;;
        test|tests|__tests__|spec) echo "# Test files" ;;
        docs|doc|documentation) echo "# Documentation" ;;
        scripts|bin) echo "# Scripts and utilities" ;;
        config|conf|cfg) echo "# Configuration files" ;;
        public|static|assets) echo "# Static assets" ;;
        build|dist|out) echo "# Build output" ;;
        node_modules) echo "# Node.js dependencies" ;;
        vendor) echo "# Vendored dependencies" ;;
        migrations) echo "# Database migrations" ;;
        seeds|seeders) echo "# Database seed data" ;;
        routes) echo "# Route definitions" ;;
        controllers) echo "# Request handlers" ;;
        models) echo "# Data models" ;;
        views|templates) echo "# View templates" ;;
        services) echo "# Business logic services" ;;
        middleware) echo "# Middleware functions" ;;
        components) echo "# UI components" ;;
        pages) echo "# Page components" ;;
        api) echo "# API endpoints" ;;
        utils|helpers|util) echo "# Utility functions" ;;
        types) echo "# Type definitions" ;;
        hooks) echo "# React hooks" ;;
        store|stores|state) echo "# State management" ;;
        lambda|functions) echo "# Serverless functions" ;;
        common|shared) echo "# Shared/common code" ;;
        packages) echo "# Monorepo packages" ;;
        tools) echo "# Development tools" ;;
        deploy|deployment|infra|infrastructure) echo "# Deployment configuration" ;;
        ci|.github|.circleci) echo "# CI/CD configuration" ;;
        examples|example|demo) echo "# Example code" ;;
        benchmark|benchmarks) echo "# Performance benchmarks" ;;
        ideas) echo "# Ideas and planning documents" ;;
        *) echo "#" ;;
    esac
}
