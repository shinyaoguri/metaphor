# metaphor

[![Release](https://img.shields.io/github/v/release/shinyaoguri/metaphor?label=version)](https://github.com/shinyaoguri/metaphor/releases/latest)
[![CI](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml/badge.svg)](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml)
[![Swift 5.10+](https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platform macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![License MIT](https://img.shields.io/github/license/shinyaoguri/metaphor)](LICENSE)

Swift + Metal creative coding library inspired by Processing / p5.js / openFrameworks.

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 5.10+

---

## Installation

### Swift Package Manager

Add metaphor to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.2.1"),
]
```

Or in Xcode: File -> Add Package Dependencies -> enter the repository URL.

---

## Quick Start

```bash
mkdir MyMetalApp && cd MyMetalApp
swift package init --type executable --name MyMetalApp
```

Edit `Package.swift`:

```swift
// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MyMetalApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "MyMetalApp",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ]
        ),
    ]
)
```

Build and run:

```bash
swift build && swift run
```

---


---


### Setup

Clone with submodules and build Syphon locally:

```bash
git clone --recursive https://github.com/shinyaoguri/metaphor.git
cd metaphor
make setup
```

### Development Commands

```bash
make setup      # Initialize submodules + build Syphon.xcframework
make build      # Build the library
make test       # Run tests (~900 tests across 10 test targets)
make clean      # Clean build artifacts
make check      # Check setup status
make docs       # Build DocC documentation
```

### How Syphon Works

- **Local development**: When `Frameworks/Syphon.xcframework` exists, Package.swift uses the local path.
- **SPM users**: When the framework doesn't exist, Package.swift fetches the pre-built XCFramework from GitHub Releases.

### Release Process

1. Tag a new version:
   ```bash
   git tag v0.X.X
   git push --tags
   ```

2. GitHub Actions will automatically:
   - Build Syphon.xcframework
   - Create a GitHub Release with the XCFramework
   - Update Package.swift with the new URL and checksum
   - Commit the changes to main

---

## Acknowledgments

Many examples in the [Examples/](Examples/) directory are Swift/Metal ports of
[Processing](https://processing.org/) example sketches, originally written by
Casey Reas, Ben Fry, and Daniel Shiffman (public domain).
See each file's header comment for specific attribution details.

- Processing: https://processing.org/
- Processing examples: https://github.com/processing/processing-examples

---
