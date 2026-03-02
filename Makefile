.PHONY: setup build clean test syphon docs docs-preview

# Default target
all: setup build

# Initial setup - clone submodules and build Syphon
setup: submodules syphon

# Update git submodules
submodules:
	@echo "Updating submodules..."
	git submodule update --init --recursive

# Build Syphon.xcframework
syphon:
	@echo "Building Syphon.xcframework..."
	./scripts/build-syphon.sh

# Build the Swift package
build:
	@echo "Building metaphor..."
	swift build

# Build release version
release:
	@echo "Building metaphor (release)..."
	swift build -c release

# Run tests
test:
	@echo "Running tests..."
	swift test

# Clean build artifacts
clean:
	@echo "Cleaning..."
	swift package clean
	rm -rf .build
	rm -rf Frameworks/Syphon.xcframework

# Full clean including submodules
clean-all: clean
	@echo "Removing submodules..."
	rm -rf Vendor/Syphon-Framework

# Check if setup is complete
check:
	@if [ -d "Frameworks/Syphon.xcframework" ]; then \
		echo "Syphon.xcframework: OK"; \
	else \
		echo "Syphon.xcframework: MISSING - run 'make setup'"; \
	fi
	@if [ -d "Vendor/Syphon-Framework" ]; then \
		echo "Syphon submodule: OK"; \
	else \
		echo "Syphon submodule: MISSING - run 'make submodules'"; \
	fi

# Build DocC documentation
# Uses manual symbol graph extraction to work around SPM binary target issue
docs:
	@echo "Building metaphor for documentation..."
	swift build
	@echo "Extracting symbol graphs..."
	@mkdir -p .build/symbol-graphs
	xcrun swift-symbolgraph-extract \
		-module-name metaphor \
		-target arm64-apple-macosx14.0 \
		-sdk "$$(xcrun --show-sdk-path)" \
		-I .build/arm64-apple-macosx/debug/Modules \
		-F Frameworks/Syphon.xcframework/macos-arm64_x86_64 \
		-minimum-access-level public \
		-skip-inherited-docs \
		-emit-extension-block-symbols \
		-output-dir .build/symbol-graphs
	@echo "Building DocC documentation..."
	xcrun docc convert Sources/metaphor/metaphor.docc \
		--additional-symbol-graph-dir .build/symbol-graphs \
		--transform-for-static-hosting \
		--hosting-base-path metaphor \
		--output-path .build/docs

# Preview DocC documentation locally
docs-preview:
	@echo "Building metaphor for documentation..."
	swift build
	@echo "Extracting symbol graphs..."
	@mkdir -p .build/symbol-graphs
	xcrun swift-symbolgraph-extract \
		-module-name metaphor \
		-target arm64-apple-macosx14.0 \
		-sdk "$$(xcrun --show-sdk-path)" \
		-I .build/arm64-apple-macosx/debug/Modules \
		-F Frameworks/Syphon.xcframework/macos-arm64_x86_64 \
		-minimum-access-level public \
		-skip-inherited-docs \
		-emit-extension-block-symbols \
		-output-dir .build/symbol-graphs
	@echo "Previewing DocC documentation..."
	xcrun docc preview Sources/metaphor/metaphor.docc \
		--additional-symbol-graph-dir .build/symbol-graphs

help:
	@echo "metaphor Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make setup        - Initialize submodules and build Syphon.xcframework"
	@echo "  make build        - Build the Swift package"
	@echo "  make release      - Build release version"
	@echo "  make test         - Run tests"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make check        - Check if setup is complete"
	@echo "  make docs         - Build DocC documentation"
	@echo "  make docs-preview - Preview DocC documentation locally"
	@echo "  make help         - Show this help"
