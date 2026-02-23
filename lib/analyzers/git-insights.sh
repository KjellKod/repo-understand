#!/usr/bin/env bash
# Analyzer: Git history analysis
# Outputs: git-insights.json to TMPDIR
# Bash 3.2 compatible
# Designed for performance on large repos (limits commit scan depth)

analyze_git_insights() {
    local repo_path="$1"
    local tmp_dir="$2"
    local output_file="$tmp_dir/git-insights.json"

    log_info "Analyzing git history..."

    # Check if this is a git repo
    if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
        log_warn "Not a git repository, skipping git insights"
        jq -n '{hotspots: [], stale_dirs: [], recent_focus_areas: [], total_commits: 0, contributors: 0}' > "$output_file"
        return
    fi

    local total_commits
    total_commits=$(git -C "$repo_path" rev-list --count HEAD 2>/dev/null || echo "0")

    # Count unique contributor emails (faster than shortlog on large repos)
    local contributors
    contributors=$(git -C "$repo_path" log --format='%ae' -5000 2>/dev/null | sort -u | wc -l | tr -d ' ')

    local six_months_ago
    six_months_ago=$(date -v-6m '+%Y-%m-%d' 2>/dev/null || date -d '6 months ago' '+%Y-%m-%d' 2>/dev/null || echo "2025-08-22")

    local three_months_ago
    three_months_ago=$(date -v-3m '+%Y-%m-%d' 2>/dev/null || date -d '3 months ago' '+%Y-%m-%d' 2>/dev/null || echo "2025-11-22")

    # Hot files (most changed in last 6 months, cap at 3000 commits for perf)
    # Write to file first, then read — avoids SIGPIPE with set -e
    git -C "$repo_path" log -3000 --since="$six_months_ago" --pretty=format: --name-only --diff-filter=ACMR 2>/dev/null \
        > "$tmp_dir/_raw_hotspots.txt" || true

    grep -v '^$' "$tmp_dir/_raw_hotspots.txt" 2>/dev/null \
        | sort | uniq -c | sort -rn | head -15 \
        > "$tmp_dir/_hotspots.txt" || true

    local hotspots_json="[]"
    while read -r count filepath; do
        [ -z "$filepath" ] && continue
        hotspots_json=$(echo "$hotspots_json" | jq --arg f "$filepath" --argjson c "$count" '. + [{"file": $f, "changes": $c}]')
    done < "$tmp_dir/_hotspots.txt"

    # Recent focus areas (directories with most changes in last 3 months)
    git -C "$repo_path" log -3000 --since="$three_months_ago" --pretty=format: --name-only --diff-filter=ACMR 2>/dev/null \
        > "$tmp_dir/_raw_focus.txt" || true

    grep -v '^$' "$tmp_dir/_raw_focus.txt" 2>/dev/null \
        | sed 's|/[^/]*$||' | sed 's|^[^/]*$|.|' \
        | sort | uniq -c | sort -rn | head -10 \
        > "$tmp_dir/_focus.txt" || true

    local focus_json="[]"
    while read -r count dirpath; do
        [ -z "$dirpath" ] && continue
        focus_json=$(echo "$focus_json" | jq --arg d "$dirpath" --argjson c "$count" '. + [{"directory": $d, "changes": $c}]')
    done < "$tmp_dir/_focus.txt"

    # Stale directories: use a single git log to find all recently-changed top-level dirs,
    # then diff against actual top-level dirs. Much faster than per-directory git log.
    git -C "$repo_path" log -3000 --since="$six_months_ago" --pretty=format: --name-only 2>/dev/null \
        > "$tmp_dir/_raw_recent.txt" || true

    # Extract unique top-level directory names from recently changed files
    grep -v '^$' "$tmp_dir/_raw_recent.txt" 2>/dev/null \
        | sed 's|/.*||' | sort -u \
        > "$tmp_dir/_recent_dirs.txt" || true

    local stale_json="[]"

    for d in "$repo_path"/*/; do
        [ ! -d "$d" ] && continue
        local dname
        dname=$(basename "$d")
        case "$dname" in
            .*|node_modules) continue ;;
        esac

        # Check if this dir appears in recent changes
        if ! grep -qx "$dname" "$tmp_dir/_recent_dirs.txt" 2>/dev/null; then
            local last_commit_date
            last_commit_date=$(git -C "$repo_path" log -1 --format='%ai' -- "$dname" 2>/dev/null | cut -d' ' -f1)
            [ -z "$last_commit_date" ] && last_commit_date="unknown"

            stale_json=$(echo "$stale_json" | jq --arg d "$dname" --arg lc "$last_commit_date" '. + [{"directory": $d, "last_change": $lc}]')
        fi
    done

    jq -n \
        --argjson hotspots "$hotspots_json" \
        --argjson stale_dirs "$stale_json" \
        --argjson recent_focus_areas "$focus_json" \
        --argjson total_commits "$total_commits" \
        --argjson contributors "$contributors" \
        '{
            hotspots: $hotspots,
            stale_dirs: $stale_dirs,
            recent_focus_areas: $recent_focus_areas,
            total_commits: $total_commits,
            contributors: $contributors
        }' > "$output_file"

    log_success "Git insights complete ($total_commits commits, $contributors contributors)"
}
