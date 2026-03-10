#!/bin/bash
# Preflight check for metaphor development environment
# Verifies all required tools and environment before setup

ERRORS=()
WARNINGS=()

# ── macOS check ──────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
    ERRORS+=("macOS is required. metaphor only supports macOS (Apple Silicon).")
fi

# ── macOS version check ─────────────────────────────────────
if command -v sw_vers &>/dev/null; then
    MACOS_VERSION=$(sw_vers -productVersion)
    MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
    if [ "$MACOS_MAJOR" -lt 14 ] 2>/dev/null; then
        ERRORS+=("macOS 14.0+ (Sonoma) is required. Current version: $MACOS_VERSION
  -> Update macOS via System Settings > General > Software Update")
    fi
fi

# ── git check ────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
    ERRORS+=("git is not installed.
  -> Install via: xcode-select --install")
fi

# ── Xcode check ─────────────────────────────────────────────
if ! command -v xcodebuild &>/dev/null; then
    ERRORS+=("Xcode is not installed. Full Xcode.app is required (not just Command Line Tools).
  -> Install Xcode from the Mac App Store:
     https://apps.apple.com/app/xcode/id497799835
  -> Then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer")
else
    XCODE_PATH=$(xcode-select -p 2>/dev/null)
    if [[ "$XCODE_PATH" == *"CommandLineTools"* ]]; then
        ERRORS+=("Xcode developer path is set to Command Line Tools.
  Current path: $XCODE_PATH
  -> If Xcode.app is installed, run:
     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  -> If Xcode.app is NOT installed, install it from the Mac App Store:
     https://apps.apple.com/app/xcode/id497799835")
    elif [ -n "$XCODE_PATH" ]; then
        # Check Xcode version
        XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')
        XCODE_MAJOR=$(echo "$XCODE_VERSION" | cut -d. -f1)
        if [ -n "$XCODE_MAJOR" ] && [ "$XCODE_MAJOR" -lt 15 ] 2>/dev/null; then
            ERRORS+=("Xcode 15.0+ is required. Current version: $XCODE_VERSION
  -> Update Xcode from the Mac App Store")
        fi

        # Check Xcode license
        if ! xcodebuild -license check &>/dev/null; then
            ERRORS+=("Xcode license has not been accepted.
  -> Run: sudo xcodebuild -license accept")
        fi
    fi
fi

# ── Swift check ──────────────────────────────────────────────
if ! command -v swift &>/dev/null; then
    ERRORS+=("Swift is not available.
  -> Swift is included with Xcode. Install Xcode first.")
else
    SWIFT_VERSION=$(swift --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    SWIFT_MAJOR=$(echo "$SWIFT_VERSION" | cut -d. -f1)
    if [ -n "$SWIFT_MAJOR" ] && [ "$SWIFT_MAJOR" -lt 6 ] 2>/dev/null; then
        ERRORS+=("Swift 6.0+ is required. Current version: $SWIFT_VERSION
  -> Update Xcode to get a newer Swift version")
    fi
fi

# ── Metal Toolchain check (skip in CI) ──────────────────────
if [ -z "$CI" ] && command -v xcodebuild &>/dev/null; then
    if ! xcodebuild -downloadComponent MetalToolchain -checkComponents &>/dev/null; then
        WARNINGS+=("Metal Toolchain is not installed. It will be downloaded automatically during setup.
  -> Or install manually: xcodebuild -downloadComponent MetalToolchain")
    fi
fi

# ── Architecture check ──────────────────────────────────────
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    WARNINGS+=("Apple Silicon (arm64) is recommended. Current architecture: $ARCH
  -> metaphor is optimized for Apple Silicon. Intel Macs may work but are not officially supported.")
fi

# ── Print results ────────────────────────────────────────────
echo ""
echo "=== metaphor preflight check ==="
echo ""

if [ ${#ERRORS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
    echo "All checks passed. Ready to setup!"
    echo ""
    exit 0
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "Warnings:"
    for i in "${!WARNINGS[@]}"; do
        echo ""
        echo "  [!] ${WARNINGS[$i]}"
    done
    echo ""
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "Errors (must fix before running setup):"
    for i in "${!ERRORS[@]}"; do
        echo ""
        echo "  [x] ${ERRORS[$i]}"
    done
    echo ""
    echo "Please resolve the errors above and run 'make setup' again."
    echo ""
    exit 1
fi

echo ""
exit 0
