#!/usr/bin/env bash
# Analyzer: Architectural pattern detection
# Outputs: patterns.json to TMPDIR
# Bash 3.2 compatible

analyze_patterns() {
    local repo_path="$1"
    local tmp_dir="$2"
    local output_file="$tmp_dir/patterns.json"

    log_info "Analyzing architectural patterns..."

    # Detect directory-based patterns
    local has_routes="false"
    local has_controllers="false"
    local has_models="false"
    local has_services="false"
    local has_components="false"
    local has_middleware="false"
    local has_views="false"
    local has_migrations="false"
    local has_seeds="false"
    local has_config="false"
    local has_tests="false"
    local has_graphql="false"

    # Search recursively but not too deep
    _find_dir() {
        find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -type d -name "$1" -maxdepth 4 2>/dev/null | head -1 | grep -q .
    }

    _find_dir "routes" && has_routes="true"
    _find_dir "controllers" && has_controllers="true"
    _find_dir "models" && has_models="true"
    _find_dir "services" && has_services="true"
    _find_dir "components" && has_components="true"
    _find_dir "middleware" && has_middleware="true"
    _find_dir "views" && has_views="true"
    _find_dir "migrations" && has_migrations="true"
    _find_dir "seeds" && has_seeds="true"
    _find_dir "seeders" && has_seeds="true"
    _find_dir "config" && has_config="true"
    _find_dir "test" && has_tests="true"
    _find_dir "tests" && has_tests="true"
    _find_dir "__tests__" && has_tests="true"
    _find_dir "spec" && has_tests="true"
    _find_dir "graphql" && has_graphql="true"

    # Determine API style
    local api_style="unknown"
    if [ "$has_graphql" = "true" ]; then
        api_style="graphql"
    fi
    # Check for GraphQL schema files
    if find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -type f \( -name '*.graphql' -o -name '*.gql' \) -maxdepth 4 2>/dev/null | head -1 | grep -q .; then
        api_style="graphql"
    fi
    if [ "$has_routes" = "true" ] || [ "$has_controllers" = "true" ]; then
        if [ "$api_style" = "graphql" ]; then
            api_style="rest+graphql"
        else
            api_style="rest"
        fi
    fi

    # Determine architecture pattern
    local arch_pattern="unknown"
    if [ "$has_controllers" = "true" ] && [ "$has_models" = "true" ] && [ "$has_views" = "true" ]; then
        arch_pattern="mvc"
    elif [ "$has_controllers" = "true" ] && [ "$has_models" = "true" ]; then
        arch_pattern="mvc-like"
    elif [ "$has_services" = "true" ] && [ "$has_models" = "true" ]; then
        arch_pattern="service-oriented"
    elif [ "$has_components" = "true" ]; then
        arch_pattern="component-based"
    elif [ "$has_routes" = "true" ] && [ "$has_middleware" = "true" ]; then
        arch_pattern="middleware-pipeline"
    fi

    # Detect config approach
    local config_approach="unknown"
    if find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -name '.env*' -maxdepth 2 2>/dev/null | head -1 | grep -q .; then
        config_approach="dotenv"
    fi
    if [ "$has_config" = "true" ]; then
        if [ "$config_approach" = "dotenv" ]; then
            config_approach="config-dir+dotenv"
        else
            config_approach="config-dir"
        fi
    fi

    # Detect additional patterns
    local detected_patterns_json="[]"

    _add_pattern() {
        local name="$1"
        local location="$2"
        detected_patterns_json=$(echo "$detected_patterns_json" | jq --arg n "$name" --arg l "$location" '. + [{"name": $n, "location": $l}]')
    }

    [ "$has_routes" = "true" ] && _add_pattern "Routes" "routes/"
    [ "$has_controllers" = "true" ] && _add_pattern "Controllers" "controllers/"
    [ "$has_models" = "true" ] && _add_pattern "Models" "models/"
    [ "$has_services" = "true" ] && _add_pattern "Services" "services/"
    [ "$has_components" = "true" ] && _add_pattern "Components" "components/"
    [ "$has_middleware" = "true" ] && _add_pattern "Middleware" "middleware/"
    [ "$has_views" = "true" ] && _add_pattern "Views" "views/"
    [ "$has_migrations" = "true" ] && _add_pattern "Migrations" "migrations/"
    [ "$has_seeds" = "true" ] && _add_pattern "Seeds/Seeders" "seeds/"
    [ "$has_tests" = "true" ] && _add_pattern "Tests" "tests/"

    # Check for serverless patterns
    if find "$repo_path" -not -path '*/.git/*' -not -path '*/node_modules/*' -type f \( -name 'serverless.yml' -o -name 'serverless.yaml' -o -name 'template.yaml' -o -name 'sam.yaml' \) -maxdepth 3 2>/dev/null | head -1 | grep -q .; then
        _add_pattern "Serverless" "serverless.yml"
    fi
    if _find_dir "lambda" || _find_dir "functions"; then
        _add_pattern "Lambda/Functions" "lambda/ or functions/"
    fi

    # Check for CI/CD
    if [ -d "$repo_path/.github/workflows" ]; then
        _add_pattern "GitHub Actions" ".github/workflows/"
    fi
    if [ -f "$repo_path/.gitlab-ci.yml" ]; then
        _add_pattern "GitLab CI" ".gitlab-ci.yml"
    fi
    if [ -f "$repo_path/Jenkinsfile" ]; then
        _add_pattern "Jenkins" "Jenkinsfile"
    fi
    jq -n \
        --arg api_style "$api_style" \
        --arg arch_pattern "$arch_pattern" \
        --arg config_approach "$config_approach" \
        --argjson has_migrations "$has_migrations" \
        --argjson has_seeds "$has_seeds" \
        --argjson has_tests "$has_tests" \
        --argjson detected_patterns "$detected_patterns_json" \
        '{
            api_style: $api_style,
            arch_pattern: $arch_pattern,
            config_approach: $config_approach,
            has_migrations: $has_migrations,
            has_seeds: $has_seeds,
            has_tests: $has_tests,
            detected_patterns: $detected_patterns
        }' > "$output_file"

    log_success "Pattern analysis complete"
}
