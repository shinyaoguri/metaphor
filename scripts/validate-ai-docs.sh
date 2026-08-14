#!/usr/bin/env bash
# Validate that AI-facing project instructions match the current codebase.
#
# Checks:
#   1. Makefile targets referenced in CLAUDE.md exist
#   2. Module names referenced match Package.swift library products
#   3. Swift source files referenced exist under Sources/
#   4. Example directories referenced exist
#   5. Makefile symbol-graphs extracts every library product
#   6. SPM dependency snippets use the stable version from README.md
#   7. Generated examples index is up to date
#   8. Example counts written in prose match the generated index
#
# Exit code: 0 if all checks pass, 1 if any fail.

set -euo pipefail

DOC_FILES=(CLAUDE.md docs/ai/README.md docs/ai/for-sketch-authors.md)
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
        # docs/ai/ はテストや example のファイル（App.swift 等）にも言及するため
        # Sources/ に加えて Tests/ と Examples/ も探索する
        if find Sources Tests Examples -name "$file" -print -quit 2>/dev/null | grep -q .; then
            pass "$doc: $file"
        else
            fail "$doc: $file — not found under Sources/, Tests/, or Examples/"
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
        # ディレクトリ参照のほか、Examples/README.md のようなファイル参照
        # （正規表現が拡張子手前まで切り出す）も許容する
        if [ -d "$epath" ] || [ -e "$epath" ] || [ -e "$epath.md" ]; then
            pass "$doc: $epath"
        else
            fail "$doc: $epath — directory or file not found"
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
    # NOTE: this list and the version-bump sed in .github/workflows/release.yml
    # ("Push release branch" step) are two halves of one contract — always
    # change them together. A file listed only here is never bumped by a
    # release yet is checked, which deadlocks the release; a file listed only
    # there is bumped but nothing stops it drifting back out of sync.
    version_docs=(
        README.en.md
        Sources/metaphor/metaphor.docc/GettingStarted.md
        llms.txt
        website/src/components/Hero.astro
    )
    for doc in "${version_docs[@]}"; do
        if [ ! -f "$doc" ]; then
            fail "$doc — file not found"
            continue
        fi
        # Anchored on `metaphor.git", from:` rather than the full URL: the
        # landing page elides the host for width ("…/metaphor.git"), and an
        # unrelated `from:` parameter label in llms.txt (tween(from:to:)) is
        # still excluded. The same anchor is used by release.yml's bump sed.
        versions=$(grep -oE 'metaphor\.git", from: "[^"]+"' "$doc" | sed -E 's/.*from: "([^"]+)".*/\1/' | sort -u || true)
        if [ -z "$versions" ]; then
            # A silent zero-match is how Hero.astro drifted to 0.4.0 unnoticed
            # (Issue #491): every file listed here is expected to carry the
            # snippet, so finding none is a failure, not a pass.
            fail "$doc — no SPM dependency snippet found (expected \`metaphor.git\", from: \"…\"\`)"
            continue
        fi
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
# 8. Example counts written in prose
# --------------------------------------------------------------------------
# Hand-written counts fall behind every time an example is added: by Issue #490
# four different numbers (278 / 274 / 270+ / 282) were in circulation. The
# generated index is the single source of truth; anything that spells the number
# out in prose is checked against it here.
echo "Checking example counts in prose..."

index_json=docs/ai/examples-index.json
if [ ! -f "$index_json" ]; then
    fail "$index_json — file not found"
else
    total_count=$(python3 -c "import json; print(json.load(open('$index_json'))['count'])")
    supported_count=$(python3 -c "import json; print(json.load(open('$index_json'))['statusCounts']['supported'])")

    # "<file>|<expected>|<regex>" — the regex matches the phrase carrying the
    # number, and must contain exactly one number so it can be read back out.
    # Keep `|` out of the regexes: it is the field separator here.
    count_claims=(
        "README.md|$total_count|サンプルが [0-9]+ 本"
        "Examples/README.md|$total_count|[0-9]+ 本の索引"
        "docs/api-stability-policy.md|$total_count|\([0-9]+ standalone packages\)"
        "website/src/i18n/ui.ts|$total_count|[0-9]+ の実行可能なサンプル"
        "website/src/i18n/ui.ts|$supported_count|うち [0-9]+ が動作確認済み"
        "website/src/i18n/ui.ts|$total_count|[0-9]+ runnable examples"
        "website/src/i18n/ui.ts|$supported_count|\([0-9]+ verified\)"
    )

    for claim in "${count_claims[@]}"; do
        claim_file=${claim%%|*}
        claim_rest=${claim#*|}
        claim_expected=${claim_rest%%|*}
        claim_pattern=${claim_rest#*|}

        if [ ! -f "$claim_file" ]; then
            fail "$claim_file — file not found"
            continue
        fi
        # A silent zero-match means the sentence was reworded: that is a failure,
        # not a pass, or the check quietly stops guarding anything (cf. #491).
        # `|| true` is load-bearing: under `set -o pipefail` a zero-match grep
        # would abort the whole script here, with no diagnostic printed at all.
        claim_found=$(grep -oE "$claim_pattern" "$claim_file" | grep -oE '[0-9]+' | sort -u || true)
        if [ -z "$claim_found" ]; then
            fail "$claim_file — no example count matched /$claim_pattern/ (reworded? update scripts/validate-ai-docs.sh)"
            continue
        fi
        for claim_number in $claim_found; do
            if [ "$claim_number" = "$claim_expected" ]; then
                pass "$claim_file: $claim_number ($claim_pattern)"
            else
                fail "$claim_file: $claim_number does not match $index_json ($claim_expected) — /$claim_pattern/"
            fi
        done
    done
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
