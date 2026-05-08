#!/usr/bin/env bash
# Validate that AI-facing project instructions match the current codebase.
#
# Checks:
#   1. Makefile targets referenced in CLAUDE.md / AGENTS.md exist
#   2. Module names referenced match Package.swift library products
#   3. Swift source files referenced exist under Sources/
#   4. Example directories referenced exist
#   5. Makefile symbol-graphs extracts every library product
#   6. SPM dependency snippets use the stable version from README.md
#
# Exit code: 0 if all checks pass, 1 if any fail.

set -euo pipefail

DOC_FILES=(CLAUDE.md AGENTS.md)
ERRORS=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

fail() { red "  FAIL: $*"; ERRORS=$((ERRORS + 1)); }
pass() { green "  OK: $*"; }

existing_docs=()
for doc in "${DOC_FILES[@]}"; do
    if [ -f "$doc" ]; then
        existing_docs+=("$doc")
    else
        fail "$doc — file not found"
    fi
done

# --------------------------------------------------------------------------
# 1. Makefile targets
# --------------------------------------------------------------------------
echo "Checking Makefile targets..."

actual_targets=$(grep -oE '^[a-zA-Z][a-zA-Z0-9_-]*:' Makefile | tr -d ':' | sort -u)
phony_targets=$(grep '^\.PHONY' Makefile | sed 's/\.PHONY://' | tr ' ' '\n' | grep -v '^$' | sort -u)
all_targets=$(printf '%s\n%s\n' "$actual_targets" "$phony_targets" | sort -u)

for doc in "${existing_docs[@]}"; do
    make_targets=$(grep -oE 'make [a-z][-a-z]*' "$doc" | awk '{print $2}' | sort -u || true)
    for target in $make_targets; do
        if echo "$all_targets" | grep -qx "$target"; then
            pass "$doc: make $target"
        else
            fail "$doc: make $target — target not found in Makefile"
        fi
    done
done

# --------------------------------------------------------------------------
# 2. Module names
# --------------------------------------------------------------------------
echo "Checking module names..."

pkg_modules=$(grep -oE '\.library\(name: "[^"]*"' Package.swift | grep -oE '"[^"]*"' | tr -d '"' | sort -u)

for doc in "${existing_docs[@]}"; do
    doc_modules=$(grep -oE 'Metaphor[A-Z][a-zA-Z]*' "$doc" | sort -u || true)
    doc_modules=$(echo "$doc_modules" | while read -r name; do
        [ -z "$name" ] && continue
        if echo "$pkg_modules" | grep -qx "$name"; then
            echo "$name"
        elif grep -qE "(import $name|: $name[,\)]|\b$name\b.*module)" "$doc"; then
            echo "$name"
        fi
    done | sort -u)

    if grep -q '`import metaphor`\|"metaphor"' "$doc"; then
        doc_modules=$(printf '%s\nmetaphor\n' "$doc_modules" | sort -u)
    fi

    for mod in $doc_modules; do
        if echo "$pkg_modules" | grep -qx "$mod"; then
            pass "$doc: module $mod"
        else
            fail "$doc: module $mod — not found in Package.swift products"
        fi
    done
done

# --------------------------------------------------------------------------
# 3. Swift source file references
# --------------------------------------------------------------------------
echo "Checking source file references..."

for doc in "${existing_docs[@]}"; do
    swift_files=$(grep -oE '[A-Za-z0-9_+]+\.swift' "$doc" | grep -v '^Package\.swift$' | sort -u || true)
    for file in $swift_files; do
        if find Sources -name "$file" -print -quit 2>/dev/null | grep -q .; then
            pass "$doc: $file"
        else
            fail "$doc: $file — not found under Sources/"
        fi
    done
done

# --------------------------------------------------------------------------
# 4. Example directory references
# --------------------------------------------------------------------------
echo "Checking example paths..."

for doc in "${existing_docs[@]}"; do
    example_paths=$(grep -oE 'Examples/[A-Za-z0-9/_-]+' "$doc" | sort -u || true)
    for epath in $example_paths; do
        if [ -d "$epath" ]; then
            pass "$doc: $epath"
        else
            fail "$doc: $epath — directory not found"
        fi
    done
done

# --------------------------------------------------------------------------
# 5. Symbol graph coverage
# --------------------------------------------------------------------------
echo "Checking symbol graph module coverage..."

symbol_graph_block=$(awk '/^symbol-graphs:/,/^# Generate llms.txt/' Makefile)
symbol_modules=$(printf '%s\n' "$symbol_graph_block" | grep -oE '\b(metaphor|Metaphor[A-Za-z0-9]+)\b' | sort -u)

for mod in $pkg_modules; do
    if echo "$symbol_modules" | grep -qx "$mod"; then
        pass "symbol-graphs includes $mod"
    else
        fail "symbol-graphs missing $mod from Package.swift products"
    fi
done

# --------------------------------------------------------------------------
# 6. SPM dependency snippet versions
# --------------------------------------------------------------------------
echo "Checking SPM dependency snippet versions..."

stable_version=$(grep -oE 'github\.com/shinyaoguri/metaphor\.git", from: "[^"]+"' README.md | head -1 | sed -E 's/.*from: "([^"]+)".*/\1/')

if [ -z "$stable_version" ]; then
    fail "README.md — could not find stable SPM dependency version"
else
    pass "README.md stable SPM version is $stable_version"
    version_docs=(Sources/metaphor/metaphor.docc/GettingStarted.md llms.txt)
    for doc in "${version_docs[@]}"; do
        if [ ! -f "$doc" ]; then
            fail "$doc — file not found"
            continue
        fi
        versions=$(grep -oE 'github\.com/shinyaoguri/metaphor\.git", from: "[^"]+"' "$doc" | sed -E 's/.*from: "([^"]+)".*/\1/' | sort -u || true)
        for version in $versions; do
            if [ "$version" = "$stable_version" ]; then
                pass "$doc: SPM version $version"
            else
                fail "$doc: SPM version $version does not match README.md $stable_version"
            fi
        done
    done
fi

# --------------------------------------------------------------------------
# 7. Generated examples index
# --------------------------------------------------------------------------
echo "Checking generated examples index..."

if python3 scripts/generate-examples-index.py --check; then
    pass "examples index is up to date"
else
    fail "examples index is out of date"
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
if [ "$ERRORS" -eq 0 ]; then
    green "All AI-facing doc checks passed."
    exit 0
else
    red "$ERRORS error(s) found. Update AI-facing docs to match the codebase."
    exit 1
fi
