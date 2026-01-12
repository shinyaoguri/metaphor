#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SYPHON_SOURCE="$ROOT_DIR/Vendor/Syphon-Framework"
BUILD_DIR="$ROOT_DIR/.build/syphon"
OUTPUT_DIR="$ROOT_DIR/Frameworks"

echo "Building Syphon.xcframework..."

# Check Xcode developer path (should be Xcode.app, not CommandLineTools)
XCODE_PATH=$(xcode-select -p)
if [[ "$XCODE_PATH" == *"CommandLineTools"* ]]; then
    echo "Error: Xcode developer path is set to Command Line Tools."
    echo "Current path: $XCODE_PATH"
    echo ""
    echo "Please switch to Xcode.app by running:"
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

# Check if Metal Toolchain is available
if ! xcodebuild -downloadComponent MetalToolchain -checkComponents 2>/dev/null; then
    echo "Metal Toolchain not found. Downloading..."
    xcodebuild -downloadComponent MetalToolchain
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
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | grep -E "(Build|error:|warning:|\*\*)"

# Check if archive was created
if [ ! -d "$BUILD_DIR/Syphon-macOS.xcarchive" ]; then
    echo "Error: Failed to create archive"
    exit 1
fi

# Create XCFramework
echo "Creating XCFramework..."
rm -rf "$OUTPUT_DIR/Syphon.xcframework"

xcodebuild -create-xcframework \
    -framework "$BUILD_DIR/Syphon-macOS.xcarchive/Products/Library/Frameworks/Syphon.framework" \
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
