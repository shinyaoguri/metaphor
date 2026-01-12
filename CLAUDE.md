# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make setup      # First-time setup: init submodules + build Syphon.xcframework
make build      # Build the library (swift build)
make test       # Run tests (swift test)
make release    # Build release version
make clean      # Clean build artifacts
make check      # Verify setup status
```

For examples:
```bash
cd Examples/RotatingCube && swift build && swift run
cd Examples/Particles && swift build && swift run
```

## Architecture Overview

metaphor is a Swift + Metal creative coding library with Syphon output support. The rendering uses a **two-pass system**:

1. **Offscreen Pass**: User renders to TextureManager's offscreen textures via `onDraw` callback
2. **Blit Pass**: Built-in pipeline blits offscreen texture to screen with aspect ratio preservation

This decouples rendering resolution from window size and enables Syphon output at fixed resolution.

### Core Components (Sources/metaphor/)

- **Core/MetaphorRenderer.swift** - Main orchestrator. Manages MTLDevice, MTLCommandQueue, TextureManager, and Syphon. Implements MTKViewDelegate and provides `onDraw` callback for user rendering code.

- **Core/TextureManager.swift** - Manages offscreen render targets (colorTexture, depthTexture). Immutable design - resizing creates new instance. Has presets: `fullHD()`, `uhd4K()`, `square()`.

- **UI/MetaphorView.swift** - SwiftUI NSViewRepresentable wrapper for MTKView. Configures FPS and connects renderer.

- **Syphon/SyphonOutput.swift** - Wraps SyphonMetalServer for inter-app video sharing. Called automatically by MetaphorRenderer when Syphon is enabled.

- **Utilities/Math.swift** - float4x4 extensions for rotation, translation, scale, lookAt, perspective. Helpers: `radians()`, `lerp()`, `smoothstep()`.

- **Utilities/Time.swift** - FrameTimer class for elapsed/delta time tracking. Animation functions: `sine01()`, `triangle()`, `sawtooth()`, `square()`.

### Typical Usage Pattern

```swift
let renderer = MetaphorRenderer(width: 1920, height: 1080)
renderer.startSyphonServer(name: "MyApp")
renderer.onDraw = { encoder, time in
    // User Metal rendering code
}
// Display with MetaphorView(renderer: renderer)
```

### Syphon Framework Handling

- **Local dev**: Package.swift uses `Frameworks/Syphon.xcframework` if present (built by `make setup`)
- **SPM users**: Falls back to downloading pre-built XCFramework from GitHub Releases

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode 15.0+
