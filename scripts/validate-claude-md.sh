#!/usr/bin/env bash
# Backward-compatible entry point for the broader AI-facing docs validator.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/validate-ai-docs.sh"
