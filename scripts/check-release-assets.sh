#!/usr/bin/env bash
#
# Release asset liveness check (Issue #316 / v1-release-plan.md W0-2, G8).
#
# SwiftPM re-fetches `binaryTarget(url:)` on every dependency resolve, so
# deleting a Release asset makes EVERY tag that points at it permanently
# unresolvable — for existing users, not just new ones. This script walks all
# `v*` tags and verifies that the URL each tag's Package.swift actually
# references still answers 200.
#
# The URL is read from the tag's own Package.swift on purpose. Checking
# "does the Release named <tag> have an asset?" would report a false failure
# for v0.2.2, whose Package.swift borrows the v0.2.1 asset (its own Release
# has no assets at all). What matters is the URL that resolve() will hit.
#
# Liveness only (HTTP status). Checksums are NOT re-verified here — that would
# download every historical xcframework weekly for no added protection, since
# assets are immutable in practice and release.yml verifies the checksum of
# each asset at publish time.
#
# Usage:
#   scripts/check-release-assets.sh            # all v* tags
#   scripts/check-release-assets.sh v0.8.0 ... # only the named tags
#
set -euo pipefail

cd "$(dirname "$0")/.."

# Tags come in as positional parameters, not an array: `${#arr[@]}` on an empty
# array is an unbound-variable error under `set -u` in bash 3.2 (macOS /bin/bash).
# Ref names cannot contain whitespace, so the unquoted split is safe.
if [ "$#" -eq 0 ]; then
  # sort -V keeps the report in version order rather than tag-creation order.
  # shellcheck disable=SC2046
  set -- $(git tag -l 'v*' | sort -V)
fi

if [ "$#" -eq 0 ]; then
  echo "::error::No v* tags found. Did the checkout fetch tags (fetch-depth: 0)?"
  exit 1
fi

total="$#"
fail=0

# head_status <url> — echo the final HTTP status of a HEAD request, following
# redirects (Release asset URLs 302 to the CDN). Retries so a transient network
# blip does not turn the weekly run into a false alarm.
head_status() {
  url="$1"
  code=""
  for attempt in 1 2 3; do
    code=$(curl -sSL -I -o /dev/null -w '%{http_code}' --max-time 60 "$url" 2>/dev/null || echo "000")
    if [ "$code" = "200" ]; then
      break
    fi
    if [ "$attempt" -lt 3 ]; then
      sleep 5
    fi
  done
  echo "$code"
}

for tag in "$@"; do
  if ! package=$(git show "$tag:Package.swift" 2>/dev/null); then
    echo "::error::$tag — no Package.swift at this tag."
    fail=1
    continue
  fi

  # The remote branch of the `useLocalSyphon ? .binaryTarget(path:) : ...`
  # ternary. Anchored on `url: "https://…"` so the local-path branch and any
  # other quoted string are ignored.
  #
  # The first match is taken with parameter expansion rather than `| head -1`:
  # under `pipefail`, head closing the pipe would SIGPIPE sed (exit 141) and
  # `set -e` would abort the whole run the day a second url: line appears.
  urls=$(printf '%s\n' "$package" | sed -n 's|.*url: "\(https://[^"]*\)".*|\1|p')
  url=${urls%%$'\n'*}

  if [ -z "$url" ]; then
    echo "::error::$tag — no binaryTarget url found in Package.swift."
    echo "          If the Package.swift layout changed, update this script's extraction."
    fail=1
    continue
  fi

  status=$(head_status "$url")
  if [ "$status" = "200" ]; then
    printf 'OK    %-24s %s\n' "$tag" "$url"
  else
    printf 'FAIL  %-24s %s (HTTP %s)\n' "$tag" "$url" "$status"
    echo "::error::$tag — binaryTarget asset is not reachable (HTTP $status): $url"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Release asset check FAILED."
  echo "A dead binaryTarget URL means 'swift package resolve' is broken for that tag,"
  echo "for everyone, forever. Re-upload the missing asset to the Release it belongs to:"
  echo "  gh release upload <tag-owning-the-asset> Syphon.xcframework.zip"
  echo "See docs/releasing.md — 配布防御(タグと Release asset)."
  exit 1
fi

echo ""
echo "Release asset check passed (${total} tag(s))."
