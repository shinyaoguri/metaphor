#!/usr/bin/env bash
# Validate that factual claims in CLAUDE.md match the current codebase.
#
# Checks:
#   1. Makefile targets referenced in CLAUDE.md exist
#   2. Module names referenced match Package.swift products
#   3. Swift source files referenced exist under Sources/
#   4. Example directories referenced exist
#
# Exit code: 0 if all checks pass, 1 if any fail.

set -euo pipefail

CLAUDE_MD="CLAUDE.md"
ERRORS=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

fail() { red "  FAIL: $*"; ERRORS=$((ERRORS + 1)); }
pass() { green "  OK: $*"; }

# --------------------------------------------------------------------------
# 1. Makefile targets
# --------------------------------------------------------------------------
echo "Checking Makefile targets..."

# Extract "make <target>" references from CLAUDE.md
make_targets=$(grep -oE 'make [a-z][-a-z]*' "$CLAUDE_MD" | awk '{print $2}' | sort -u)

# Extract actual targets from Makefile (lines like "target-name:" at column 0)
actual_targets=$(grep -oE '^[a-zA-Z][a-zA-Z0-9_-]*:' Makefile | tr -d ':' | sort -u)
# Also include targets from .PHONY line
phony_targets=$(grep '^\.PHONY' Makefile | sed 's/\.PHONY://' | tr ' ' '\n' | grep -v '^$' | sort -u)
all_targets=$(printf '%s\n%s\n' "$actual_targets" "$phony_targets" | sort -u)

for target in $make_targets; do
    if echo "$all_targets" | grep -qx "$target"; then
        pass "make $target"
    else
        fail "make $target — target not found in Makefile"
    fi
done

# --------------------------------------------------------------------------
# 2. Module names
# --------------------------------------------------------------------------
echo "Checking module names..."

# Extract module names from Package.swift (library product names)
pkg_modules=$(grep -oE '\.library\(name: "[^"]*"' Package.swift | grep -oE '"[^"]*"' | tr -d '"' | sort -u)

# Extract Metaphor* module names from CLAUDE.md.
# Only match names that look like module identifiers (used as imports or
# standalone references), not protocol/type names like MetaphorPlugin.
claude_modules=$(grep -oE 'Metaphor[A-Z][a-zA-Z]*' "$CLAUDE_MD" | sort -u)
# Filter to only names that appear as Package.swift product prefixes (Metaphor + capitalized word)
# and exclude known non-module patterns (types/protocols)
claude_modules=$(echo "$claude_modules" | while read -r name; do
    # If it's in Package.swift products, it's a real module
    if echo "$pkg_modules" | grep -qx "$name"; then
        echo "$name"
    # If it's not a product but IS in the module list format in CLAUDE.md, flag it
    elif grep -qE "(import $name|: $name[,\)]|\b$name\b.*module)" "$CLAUDE_MD"; then
        echo "$name"
    fi
done | sort -u)
# Also check for the umbrella "metaphor" module
if grep -q '`import metaphor`\|"metaphor"' "$CLAUDE_MD"; then
    claude_modules=$(printf '%s\nmetaphor\n' "$claude_modules" | sort -u)
fi

for mod in $claude_modules; do
    if echo "$pkg_modules" | grep -qx "$mod"; then
        pass "module $mod"
    else
        fail "module $mod — not found in Package.swift products"
    fi
done

# --------------------------------------------------------------------------
# 3. Swift source file references
# --------------------------------------------------------------------------
echo "Checking source file references..."

# Extract *.swift file names from CLAUDE.md (e.g., "Sketch+Shapes.swift")
# Exclude Package.swift which is a project file, not a source file
swift_files=$(grep -oE '[A-Za-z0-9_+]+\.swift' "$CLAUDE_MD" | grep -v '^Package\.swift$' | sort -u)

for file in $swift_files; do
    # Search in Sources/ directory
    if find Sources -name "$file" -print -quit 2>/dev/null | grep -q .; then
        pass "$file"
    else
        fail "$file — not found under Sources/"
    fi
done

# --------------------------------------------------------------------------
# 4. Example directory references
# --------------------------------------------------------------------------
echo "Checking example paths..."

# Extract Examples/ paths from CLAUDE.md
example_paths=$(grep -oE 'Examples/[A-Za-z0-9/_-]+' "$CLAUDE_MD" | sort -u)

for epath in $example_paths; do
    if [ -d "$epath" ]; then
        pass "$epath"
    else
        fail "$epath — directory not found"
    fi
done

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
if [ "$ERRORS" -eq 0 ]; then
    green "All CLAUDE.md references are valid."
    exit 0
else
    red "$ERRORS error(s) found. Update CLAUDE.md to match the codebase."
    exit 1
fi
