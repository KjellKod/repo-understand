#!/usr/bin/env bash
# Import parser for JavaScript/TypeScript files
# Extracts require() and import statements, resolves relative paths
# Bash 3.2 compatible -- no associative arrays, no readarray, no ${var,,}
#
# Output format (pipe-separated, one per line to stdout):
#   raw|resolved|type|is_external
#
# Types: commonjs, esm, dynamic
# is_external: true or false
# resolved: absolute path or empty for dynamic/external

# Resolve a module specifier to an absolute file path.
# Tries extensions: .js, .ts, .tsx, .json, /index.js, /index.ts
# Args: base_dir specifier
# Outputs: resolved absolute path or empty string
_resolve_module_path() {
    local base_dir="$1"
    local specifier="$2"

    # Build candidate path
    local candidate
    if [ "${specifier#/}" != "$specifier" ]; then
        # Absolute path
        candidate="$specifier"
    else
        # Relative path
        candidate="$base_dir/$specifier"
    fi

    # Normalize path (remove ./ and ../ components)
    # Use cd+pwd for reliable normalization
    local dir_part base_part
    dir_part=$(dirname "$candidate")
    base_part=$(basename "$candidate")

    if [ -d "$dir_part" ]; then
        dir_part=$(cd "$dir_part" 2>/dev/null && pwd) || return
    else
        # Directory doesn't exist, can't resolve
        return
    fi
    candidate="$dir_part/$base_part"

    # If exact file exists, return it
    if [ -f "$candidate" ]; then
        echo "$candidate"
        return
    fi

    # Try extensions
    local ext
    for ext in .js .ts .tsx .json; do
        if [ -f "${candidate}${ext}" ]; then
            echo "${candidate}${ext}"
            return
        fi
    done

    # Try index files (directory resolution)
    for ext in /index.js /index.ts; do
        if [ -f "${candidate}${ext}" ]; then
            echo "${candidate}${ext}"
            return
        fi
    done

    # Could not resolve
    return
}

# Parse imports from a single JavaScript/TypeScript file.
# Args: file_path (absolute)
# Outputs: pipe-separated records to stdout
parse_imports() {
    local file_path="$1"

    # Validate input
    if [ ! -f "$file_path" ]; then
        return 0
    fi

    # Skip binary files (check first bytes)
    if file "$file_path" 2>/dev/null | grep -q "binary"; then
        return 0
    fi

    local base_dir
    base_dir=$(dirname "$file_path")

    local line raw specifier

    # Process CommonJS require() statements
    # Match: require('...') or require("...")
    # Note: "|| true" prevents set -e from killing the caller when grep finds no matches
    grep -n 'require(' "$file_path" 2>/dev/null | while IFS= read -r line; do
        # Extract the argument to require()
        # Handle require('module'), require("module"), require(variable)
        specifier=$(echo "$line" | sed -n "s/.*require( *['\"]\\([^'\"]*\\)['\"].*/\\1/p")

        if [ -z "$specifier" ]; then
            # Could be a dynamic require (variable argument)
            raw=$(echo "$line" | sed -n "s/.*require( *\\([^)]*\\)).*/\\1/p")
            if [ -n "$raw" ]; then
                echo "${raw}||dynamic|false"
            fi
            continue
        fi

        raw="$specifier"

        # Check if external (doesn't start with . or /)
        if [ "${specifier#.}" = "$specifier" ] && [ "${specifier#/}" = "$specifier" ]; then
            echo "${raw}||commonjs|true"
            continue
        fi

        # Resolve relative/absolute path
        local resolved
        resolved=$(_resolve_module_path "$base_dir" "$specifier")
        echo "${raw}|${resolved}|commonjs|false"
    done || true

    # Process ESM import statements
    # Match: import ... from '...' or import '...' (side-effect)
    # Skip: import type { ... } from '...' (TypeScript type-only imports)
    # Note: "|| true" prevents set -e from killing the caller when grep finds no matches
    grep -n 'import ' "$file_path" 2>/dev/null | grep -v 'import type ' | while IFS= read -r line; do
        # Try: import X from 'module' or import { X } from 'module' or import 'module'
        specifier=$(echo "$line" | sed -n "s/.*from *['\"]\\([^'\"]*\\)['\"].*/\\1/p")

        if [ -z "$specifier" ]; then
            # Try side-effect import: import 'module'
            specifier=$(echo "$line" | sed -n "s/.*import *['\"]\\([^'\"]*\\)['\"].*/\\1/p")
        fi

        if [ -z "$specifier" ]; then
            continue
        fi

        raw="$specifier"

        # Check if external
        if [ "${specifier#.}" = "$specifier" ] && [ "${specifier#/}" = "$specifier" ]; then
            echo "${raw}||esm|true"
            continue
        fi

        # Resolve relative/absolute path
        local resolved
        resolved=$(_resolve_module_path "$base_dir" "$specifier")
        echo "${raw}|${resolved}|esm|false"
    done || true
}
