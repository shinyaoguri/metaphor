#!/usr/bin/env bash
#
# Root manifest must stay free of binary targets (#792 / ADR-0014).
#
# SwiftPM downloads a remote `binaryTarget(url:)` for EVERY consumer that
# resolves the package — even when no product that depends on it is used, and
# even with package traits (resolution is not gated by either; measured in
# #792, 所見 1-a). That is why the Syphon.xcframework moved into its own package
# (shinyaoguri/metaphor-syphon): a binary target in this manifest would drag the
# download, the release-asset coupling and the sourcekit-lsp indexing failure
# (#578) back to every `import metaphor` user.
#
# Two checks, from cheap to thorough:
#   1. Package.swift contains no `.binaryTarget(` declaration.
#   2. A throw-away consumer that depends on this checkout by path resolves
#      without producing `.build/artifacts` (the directory SwiftPM uses for
#      downloaded / extracted binary artifacts).
#
# Usage: scripts/check-no-binary-targets.sh   (from anywhere; runs in the repo root)
#
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

# --- 1. Manifest grep ---------------------------------------------------------
# Match a declaration anywhere on a non-comment line (the old manifest spelled it
# `? .binaryTarget(name:path:)` / `: .binaryTarget(name:url:checksum:)`).
if grep -nE '^[^/]*\.binaryTarget\(' Package.swift; then
  echo "::error::Package.swift declares a binaryTarget. Binary artifacts belong in a separate package (ADR-0014)."
  fail=1
else
  echo "OK: Package.swift declares no binaryTarget."
fi

# --- 2. Consumer resolve ------------------------------------------------------
# `swift package resolve` fetches dependencies (including binary artifacts) without
# compiling anything, so this stays cheap. The consumer depends on the umbrella
# product so that every library target is part of the graph.
repo_root="$(pwd -P)"
consumer="$(mktemp -d "${TMPDIR:-/tmp}/metaphor-consumer.XXXXXX")"
trap 'rm -rf "$consumer"' EXIT

mkdir -p "$consumer/Sources/Consumer"
cat > "$consumer/Package.swift" <<EOF
// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Consumer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "metaphor", path: "${repo_root}")],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [.product(name: "metaphor", package: "metaphor")]
        ),
    ]
)
EOF
echo 'import metaphor' > "$consumer/Sources/Consumer/main.swift"

if ! (cd "$consumer" && swift package resolve >/dev/null); then
  echo "::error::A consumer depending on this checkout failed to resolve."
  fail=1
# SwiftPM creates an empty .build/artifacts directory on every resolve; only
# entries inside it mean a binary artifact was actually fetched / extracted.
elif [ -d "$consumer/.build/artifacts" ] && [ -n "$(ls -A "$consumer/.build/artifacts")" ]; then
  echo "::error::Resolving a consumer populated .build/artifacts — a binary artifact is still being downloaded:"
  find "$consumer/.build/artifacts" -maxdepth 3 | sed 's/^/          /'
  fail=1
else
  echo "OK: a path-dependent consumer resolves without .build/artifacts."
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Binary target check FAILED — see docs/adr/0014-viewer-frame-ipc-and-syphon-plugin.md."
  exit 1
fi
echo "Binary target check passed."
