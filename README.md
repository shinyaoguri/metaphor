# metaphor

Swift + Metal creative coding library inspired by Processing / p5.js / openFrameworks.

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 6.0+

---

## Installation

### Swift Package Manager

Add metaphor to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.2.0"),
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
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyMetalApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.2.0"),
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
make test       # Run tests (~500 tests across 4 test targets)
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
