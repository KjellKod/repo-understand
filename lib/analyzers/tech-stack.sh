#!/usr/bin/env bash
# Analyzer: Language, framework, and database detection
# Outputs: tech-stack.json to TMPDIR
# Bash 3.2 compatible

analyze_tech_stack() {
    local repo_path="$1"
    local tmp_dir="$2"
    local output_file="$tmp_dir/tech-stack.json"

    log_info "Analyzing tech stack..."

    # --- Languages ---
    local languages_json="[]"
    local ext_file="$tmp_dir/_ext_counts.txt"

    # If structure analyzer already ran, reuse its data; otherwise compute
    if [ ! -f "$ext_file" ]; then
        find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -type f -name '*.*' 2>/dev/null \
            | sed 's/.*\.//' | tr '[:upper:]' '[:lower:]' \
            | sort | uniq -c | sort -rn | head -15 > "$ext_file"
    fi

    # Map extensions to language names
    while read -r count ext; do
        local lang_name=""
        case "$ext" in
            ts|tsx) lang_name="TypeScript" ;;
            js|jsx|mjs|cjs) lang_name="JavaScript" ;;
            coffee) lang_name="CoffeeScript" ;;
            py) lang_name="Python" ;;
            go) lang_name="Go" ;;
            rs) lang_name="Rust" ;;
            java) lang_name="Java" ;;
            rb) lang_name="Ruby" ;;
            php) lang_name="PHP" ;;
            c|h) lang_name="C" ;;
            cpp|cc|cxx|hpp) lang_name="C++" ;;
            cs) lang_name="C#" ;;
            swift) lang_name="Swift" ;;
            kt|kts) lang_name="Kotlin" ;;
            sh|bash|zsh) lang_name="Shell" ;;
            md) lang_name="Markdown" ;;
            json) lang_name="JSON" ;;
            yaml|yml) lang_name="YAML" ;;
            css|scss|sass|less) lang_name="CSS" ;;
            html|htm) lang_name="HTML" ;;
            sql) lang_name="SQL" ;;
            *) continue ;;
        esac
        if [ -n "$lang_name" ]; then
            languages_json=$(echo "$languages_json" | jq --arg n "$lang_name" --arg e "$ext" --argjson c "$count" '. + [{"name": $n, "extension": $e, "file_count": $c}]')
        fi
    done < "$ext_file"

    # Additional language markers
    local has_typescript="false"
    [ -f "$repo_path/tsconfig.json" ] && has_typescript="true"
    find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name 'tsconfig.json' -maxdepth 3 2>/dev/null | head -1 | grep -q . && has_typescript="true"

    # --- Frameworks ---
    local frameworks_json="[]"
    local _added_frameworks=""

    # Collect all package.json files
    local all_deps_file="$tmp_dir/_all_deps.txt"
    find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name 'package.json' -maxdepth 4 2>/dev/null | while IFS= read -r pjson; do
        jq -r '(.dependencies // {} | keys[]), (.devDependencies // {} | keys[])' "$pjson" 2>/dev/null
    done | sort -u > "$all_deps_file"

    # Framework detection map
    _check_dep() {
        grep -q "^$1$" "$all_deps_file" 2>/dev/null
    }

    _add_framework() {
        local name="$1"
        local category="$2"
        local role="$3"
        # Deduplicate by name
        case "$_added_frameworks" in
            *"|$name|"*) return 0 ;;
        esac
        _added_frameworks="${_added_frameworks}|$name|"
        frameworks_json=$(echo "$frameworks_json" | jq --arg n "$name" --arg c "$category" --arg r "$role" '. + [{"name": $n, "category": $c, "role": $r}]')
    }

    _check_dep "express" && _add_framework "Express" "framework" "HTTP server framework"
    _check_dep "koa" && _add_framework "Koa" "framework" "HTTP server framework"
    _check_dep "fastify" && _add_framework "Fastify" "framework" "HTTP server framework"
    _check_dep "hapi" && _add_framework "Hapi" "framework" "HTTP server framework"
    _check_dep "@hapi/hapi" && _add_framework "Hapi" "framework" "HTTP server framework"
    _check_dep "react" && _add_framework "React" "frontend" "UI library"
    _check_dep "next" && _add_framework "Next.js" "frontend" "React framework"
    _check_dep "vue" && _add_framework "Vue.js" "frontend" "UI framework"
    _check_dep "angular" && _add_framework "Angular" "frontend" "UI framework"
    _check_dep "@angular/core" && _add_framework "Angular" "frontend" "UI framework"
    _check_dep "angularjs" && _add_framework "AngularJS" "frontend" "Legacy UI framework"
    # Check for AngularJS via bower or script tags
    if find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name 'bower.json' -maxdepth 3 2>/dev/null | head -1 | grep -q .; then
        if find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name 'bower.json' -maxdepth 3 -exec grep -l 'angular' {} + 2>/dev/null | head -1 | grep -q .; then
            _add_framework "AngularJS" "frontend" "Legacy UI framework (via Bower)"
        fi
    fi
    _check_dep "svelte" && _add_framework "Svelte" "frontend" "UI framework"
    { _check_dep "django" || [ -f "$repo_path/manage.py" ]; } && _add_framework "Django" "framework" "Python web framework"
    _check_dep "flask" && _add_framework "Flask" "framework" "Python web framework"
    _check_dep "electron" && _add_framework "Electron" "desktop" "Desktop application framework"
    _check_dep "socket.io" && _add_framework "Socket.IO" "realtime" "WebSocket framework"
    _check_dep "graphql" && _add_framework "GraphQL" "api" "Query language"
    _check_dep "apollo-server" && _add_framework "Apollo Server" "api" "GraphQL server"
    # frameworks_json is already a complete JSON array

    # --- Databases ---
    local datastores_json="[]"
    local _added_datastores=""

    _add_datastore() {
        local name="$1"
        local driver="$2"
        # Deduplicate by name
        case "$_added_datastores" in
            *"|$name|"*) return 0 ;;
        esac
        _added_datastores="${_added_datastores}|$name|"
        datastores_json=$(echo "$datastores_json" | jq --arg n "$name" --arg d "$driver" '. + [{"name": $n, "driver": $d}]')
    }

    _check_dep "mongoose" && _add_datastore "MongoDB" "mongoose"
    _check_dep "mongodb" && _add_datastore "MongoDB" "mongodb"
    _check_dep "pg" && _add_datastore "PostgreSQL" "pg"
    _check_dep "sequelize" && _add_datastore "SQL (via Sequelize)" "sequelize"
    _check_dep "knex" && _add_datastore "SQL (via Knex)" "knex"
    _check_dep "typeorm" && _add_datastore "SQL (via TypeORM)" "typeorm"
    _check_dep "prisma" && _add_datastore "SQL (via Prisma)" "prisma"
    _check_dep "@prisma/client" && _add_datastore "SQL (via Prisma)" "@prisma/client"
    _check_dep "redis" && _add_datastore "Redis" "redis"
    _check_dep "ioredis" && _add_datastore "Redis" "ioredis"
    _check_dep "mysql" && _add_datastore "MySQL" "mysql"
    _check_dep "mysql2" && _add_datastore "MySQL" "mysql2"
    _check_dep "sqlite3" && _add_datastore "SQLite" "sqlite3"
    _check_dep "better-sqlite3" && _add_datastore "SQLite" "better-sqlite3"
    _check_dep "elasticsearch" && _add_datastore "Elasticsearch" "elasticsearch"
    _check_dep "@elastic/elasticsearch" && _add_datastore "Elasticsearch" "@elastic/elasticsearch"

    # Check Python requirements
    if [ -f "$repo_path/requirements.txt" ]; then
        grep -qi 'psycopg2\|asyncpg' "$repo_path/requirements.txt" && _add_datastore "PostgreSQL" "psycopg2"
        grep -qi 'pymongo' "$repo_path/requirements.txt" && _add_datastore "MongoDB" "pymongo"
        grep -qi 'redis' "$repo_path/requirements.txt" && _add_datastore "Redis" "redis-py"
    fi
    # datastores_json is already a complete JSON array

    # --- Build Tools ---
    local build_tools_json="[]"
    local _added_build_tools=""

    _add_build_tool() {
        local name="$1"
        local role="$2"
        # Deduplicate by name
        case "$_added_build_tools" in
            *"|$name|"*) return 0 ;;
        esac
        _added_build_tools="${_added_build_tools}|$name|"
        build_tools_json=$(echo "$build_tools_json" | jq --arg n "$name" --arg r "$role" '. + [{"name": $n, "role": $r}]')
    }

    _check_dep "webpack" && _add_build_tool "Webpack" "Module bundler"
    _check_dep "vite" && _add_build_tool "Vite" "Build tool and dev server"
    _check_dep "esbuild" && _add_build_tool "esbuild" "JavaScript bundler"
    _check_dep "rollup" && _add_build_tool "Rollup" "Module bundler"
    _check_dep "parcel" && _add_build_tool "Parcel" "Zero-config bundler"
    _check_dep "gulp" && _add_build_tool "Gulp" "Task runner"
    _check_dep "grunt" && _add_build_tool "Grunt" "Task runner"
    _check_dep "babel" && _add_build_tool "Babel" "JavaScript transpiler"
    _check_dep "@babel/core" && _add_build_tool "Babel" "JavaScript transpiler"
    _check_dep "typescript" && _add_build_tool "TypeScript" "Type checker and transpiler"
    _check_dep "coffee-script" && _add_build_tool "CoffeeScript" "CoffeeScript compiler"
    _check_dep "coffeescript" && _add_build_tool "CoffeeScript" "CoffeeScript compiler"
    [ -f "$repo_path/Makefile" ] && _add_build_tool "Make" "Build automation"
    [ -f "$repo_path/Dockerfile" ] && _add_build_tool "Docker" "Containerization"
    find "$repo_path" -not -path '*/.git/*' -name 'docker-compose*.yml' -maxdepth 2 2>/dev/null | head -1 | grep -q . && _add_build_tool "Docker Compose" "Multi-container orchestration"
    # build_tools_json is already a complete JSON array

    # --- Test Tools ---
    local test_tools_json="[]"
    local _added_test_tools=""

    _add_test_tool() {
        local name="$1"
        local role="$2"
        # Deduplicate by name
        case "$_added_test_tools" in
            *"|$name|"*) return 0 ;;
        esac
        _added_test_tools="${_added_test_tools}|$name|"
        test_tools_json=$(echo "$test_tools_json" | jq --arg n "$name" --arg r "$role" '. + [{"name": $n, "role": $r}]')
    }

    _check_dep "jest" && _add_test_tool "Jest" "Test framework"
    _check_dep "mocha" && _add_test_tool "Mocha" "Test framework"
    _check_dep "chai" && _add_test_tool "Chai" "Assertion library"
    _check_dep "jasmine" && _add_test_tool "Jasmine" "Test framework"
    _check_dep "vitest" && _add_test_tool "Vitest" "Test framework"
    _check_dep "cypress" && _add_test_tool "Cypress" "E2E testing"
    _check_dep "playwright" && _add_test_tool "Playwright" "E2E testing"
    _check_dep "@playwright/test" && _add_test_tool "Playwright" "E2E testing"
    _check_dep "supertest" && _add_test_tool "Supertest" "HTTP testing"
    _check_dep "sinon" && _add_test_tool "Sinon" "Mocking library"
    _check_dep "nock" && _add_test_tool "Nock" "HTTP mocking"
    _check_dep "nyc" && _add_test_tool "NYC/Istanbul" "Code coverage"
    _check_dep "c8" && _add_test_tool "c8" "Code coverage"
    _check_dep "eslint" && _add_test_tool "ESLint" "Linter"
    _check_dep "prettier" && _add_test_tool "Prettier" "Code formatter"

    # Python test tools
    if [ -f "$repo_path/requirements.txt" ] || [ -f "$repo_path/setup.py" ] || [ -f "$repo_path/pyproject.toml" ]; then
        find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name 'conftest.py' -maxdepth 3 2>/dev/null | head -1 | grep -q . && _add_test_tool "pytest" "Python test framework"
    fi
    # test_tools_json is already a complete JSON array

    # Write JSON output
    jq -n \
        --argjson languages "$languages_json" \
        --argjson frameworks "$frameworks_json" \
        --argjson datastores "$datastores_json" \
        --argjson build_tools "$build_tools_json" \
        --argjson test_tools "$test_tools_json" \
        --argjson has_typescript "$has_typescript" \
        '{
            languages: $languages,
            frameworks: $frameworks,
            datastores: $datastores,
            build_tools: $build_tools,
            test_tools: $test_tools,
            has_typescript: $has_typescript
        }' > "$output_file"

    log_success "Tech stack analysis complete"
}
