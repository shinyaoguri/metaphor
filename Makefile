.PHONY: setup build clean test test-verbose test-coverage test-lcov syphon preflight docs docs-preview examples examples-check examples-list

# Default target
all: setup build

# Preflight check - verify required tools and environment
preflight:
	@./scripts/preflight-check.sh

# Initial setup - clone submodules and build Syphon
setup: preflight submodules syphon

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

# Run tests with verbose output
test-verbose:
	@echo "Running tests (verbose)..."
	swift test --verbose

# Run tests with code coverage report
test-coverage:
	@echo "Running tests with coverage..."
	swift test --enable-code-coverage
	@echo ""
	@echo "Coverage report:"
	@xcrun llvm-cov report \
		$$(swift test --enable-code-coverage --show-codecov-path 2>/dev/null || echo ".build/debug/metaphorPackageTests.xctest/Contents/MacOS/metaphorPackageTests") \
		-instr-profile=.build/debug/codecov/default.profdata \
		-ignore-filename-regex='Tests/|\.build/' 2>/dev/null || \
	echo "  (coverage report generation requires a successful test run with --enable-code-coverage)"

# Generate LCOV coverage data for CI integration
test-lcov:
	@echo "Running tests with coverage (LCOV)..."
	swift test --enable-code-coverage
	@xcrun llvm-cov export \
		$$(swift test --enable-code-coverage --show-codecov-path 2>/dev/null || echo ".build/debug/metaphorPackageTests.xctest/Contents/MacOS/metaphorPackageTests") \
		-instr-profile=.build/debug/codecov/default.profdata \
		-ignore-filename-regex='Tests/|\.build/' \
		-format=lcov > .build/coverage.lcov 2>/dev/null || true
	@echo "LCOV written to .build/coverage.lcov"

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
	@for module in metaphor MetaphorCore \
		MetaphorAudio MetaphorNetwork MetaphorPhysics MetaphorML \
		MetaphorNoise MetaphorMPS MetaphorCoreImage \
		MetaphorRenderGraph MetaphorSceneGraph; do \
		xcrun swift-symbolgraph-extract \
			-module-name $$module \
			-target arm64-apple-macosx14.0 \
			-sdk "$$(xcrun --show-sdk-path)" \
			-I .build/arm64-apple-macosx/debug/Modules \
			-F Frameworks/Syphon.xcframework/macos-arm64_x86_64 \
			-minimum-access-level public \
			-skip-inherited-docs \
			-emit-extension-block-symbols \
			-output-dir .build/symbol-graphs; \
	done
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
	@for module in metaphor MetaphorCore \
		MetaphorAudio MetaphorNetwork MetaphorPhysics MetaphorML \
		MetaphorNoise MetaphorMPS MetaphorCoreImage \
		MetaphorRenderGraph MetaphorSceneGraph; do \
		xcrun swift-symbolgraph-extract \
			-module-name $$module \
			-target arm64-apple-macosx14.0 \
			-sdk "$$(xcrun --show-sdk-path)" \
			-I .build/arm64-apple-macosx/debug/Modules \
			-F Frameworks/Syphon.xcframework/macos-arm64_x86_64 \
			-minimum-access-level public \
			-skip-inherited-docs \
			-emit-extension-block-symbols \
			-output-dir .build/symbol-graphs; \
	done
	@echo "Previewing DocC documentation..."
	xcrun docc preview Sources/metaphor/metaphor.docc \
		--additional-symbol-graph-dir .build/symbol-graphs

# Run examples in parallel (excludes _Legacy/ by default)
examples:
	@./scripts/run-examples.sh --parallel 10

# Build-only verification of all examples (parallel)
examples-check:
	@./scripts/run-examples.sh --build-only --parallel 10

# Run examples sequentially (interactive, with note prompts)
examples-seq:
	@./scripts/run-examples.sh

# List all available examples
examples-list:
	@./scripts/run-examples.sh --list

help:
	@echo "metaphor Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make preflight      - Check required tools and environment"
	@echo "  make setup          - Initialize submodules and build Syphon.xcframework"
	@echo "  make build          - Build the Swift package"
	@echo "  make release        - Build release version"
	@echo "  make test           - Run tests"
	@echo "  make test-verbose   - Run tests with verbose output"
	@echo "  make test-coverage  - Run tests and show coverage report"
	@echo "  make test-lcov     - Run tests and generate LCOV for CI"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make check          - Check if setup is complete"
	@echo "  make docs           - Build DocC documentation"
	@echo "  make docs-preview   - Preview DocC documentation locally"
	@echo "  make examples       - Run examples in parallel (10 workers)"
	@echo "  make examples-seq   - Run examples sequentially (interactive)"
	@echo "  make examples-check - Build-only verification (parallel)"
	@echo "  make examples-list  - List all available examples"
	@echo "  make help           - Show this help"
