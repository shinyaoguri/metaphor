#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SYPHON_SOURCE="$ROOT_DIR/Vendor/Syphon-Framework"
BUILD_DIR="$ROOT_DIR/.build/syphon"
OUTPUT_DIR="$ROOT_DIR/Frameworks"

echo "Building Syphon.xcframework..."

# Quick sanity check (full validation is done by preflight-check.sh)
XCODE_PATH=$(xcode-select -p 2>/dev/null)
if [[ -z "$XCODE_PATH" || "$XCODE_PATH" == *"CommandLineTools"* ]]; then
    echo "Error: Xcode.app is required. Run 'make preflight' for details."
    exit 1
fi

# Check if Metal Toolchain is available (skip in CI)
if [ -z "$CI" ]; then
    if ! xcodebuild -downloadComponent MetalToolchain -checkComponents 2>/dev/null; then
        echo "Metal Toolchain not found. Downloading..."
        xcodebuild -downloadComponent MetalToolchain
    fi
fi

# Check if submodule exists
if [ ! -d "$SYPHON_SOURCE" ]; then
    echo "Error: Syphon-Framework submodule not found."
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

cd "$SYPHON_SOURCE"

# Build for macOS (arm64 + x86_64)
echo "Building for macOS..."
xcodebuild archive \
    -scheme Syphon \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$BUILD_DIR/Syphon-macOS.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO

# Check if archive was created
if [ ! -d "$BUILD_DIR/Syphon-macOS.xcarchive" ]; then
    echo "Error: Failed to create archive"
    exit 1
fi

# Find the framework in the archive (path may vary)
echo "Searching for framework in archive..."
FRAMEWORK_PATH=$(find "$BUILD_DIR/Syphon-macOS.xcarchive" -name "Syphon.framework" -type d | head -1)

if [ -z "$FRAMEWORK_PATH" ]; then
    echo "Error: Syphon.framework not found in archive"
    echo "Archive contents:"
    find "$BUILD_DIR/Syphon-macOS.xcarchive" -type d
    exit 1
fi

echo "Found framework at: $FRAMEWORK_PATH"

# Create XCFramework
echo "Creating XCFramework..."
rm -rf "$OUTPUT_DIR/Syphon.xcframework"

xcodebuild -create-xcframework \
    -framework "$FRAMEWORK_PATH" \
    -output "$OUTPUT_DIR/Syphon.xcframework"

# Verify
if [ -d "$OUTPUT_DIR/Syphon.xcframework" ]; then
    echo ""
    echo "Success! Syphon.xcframework created at:"
    echo "  $OUTPUT_DIR/Syphon.xcframework"
    echo ""
    ls -la "$OUTPUT_DIR/Syphon.xcframework"
else
    echo "Error: Failed to create XCFramework"
    exit 1
fi

# Cleanup
rm -rf "$BUILD_DIR"

echo ""
echo "Done!"
