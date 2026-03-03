# metaphor

Swift + Metal creative coding library with Syphon output support.

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
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.1.0"),
]
```

Or in Xcode: File → Add Package Dependencies → enter the repository URL.

---

## Quick Start

### 1. Create your project

```bash
mkdir MyMetalApp && cd MyMetalApp
swift package init --type executable --name MyMetalApp
```

### 2. Edit Package.swift

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyMetalApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.1.0"),
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

### 3. Write your app

Replace `Sources/MyMetalApp/main.swift`:

```swift
import SwiftUI
import metaphor

@main
struct MyMetalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var renderer: MetaphorRenderer?

    var body: some View {
        Group {
            if let renderer = renderer {
                MetaphorView(renderer: renderer)
            } else {
                Text("Initializing...")
            }
        }
        .onAppear { setupRenderer() }
    }

    private func setupRenderer() {
        guard let renderer = MetaphorRenderer(width: 1920, height: 1080) else { return }
        renderer.startSyphonServer(name: "MyMetalApp")

        renderer.onDraw = { encoder, time in
            // Your Metal rendering code here
        }

        self.renderer = renderer
    }
}
```

### 4. Build and run

```bash
swift build && swift run
```

---


## API Reference

### MetaphorRenderer

Main renderer class that manages Metal device, command queue, and Syphon output.

```swift
let renderer = MetaphorRenderer(
    width: 1920,
    height: 1080,
    clearColor: .black
)

// Syphon output
renderer.startSyphonServer(name: "ServerName")
renderer.stopSyphonServer()

// Draw callback
renderer.onDraw = { encoder, time in
    // encoder: MTLRenderCommandEncoder
    // time: elapsed time in seconds
}

// Access properties
renderer.device          // MTLDevice
renderer.commandQueue    // MTLCommandQueue
renderer.elapsedTime     // Double
```

### MetaphorView

SwiftUI view for displaying Metal content.

```swift
MetaphorView(renderer: renderer, preferredFPS: 60)
```

### TextureManager

Manages offscreen render targets.

```swift
// Presets
let texture = TextureManager.fullHD(device: device)    // 1920x1080
let texture = TextureManager.uhd4K(device: device)     // 3840x2160
let texture = TextureManager.square(device: device, size: 1024)

// Custom
let texture = TextureManager(
    device: device,
    width: 1280,
    height: 720,
    clearColor: MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
)
```

### SyphonOutput

Direct Syphon server control.

```swift
let syphon = SyphonOutput(device: device, name: "ServerName")
syphon.publish(texture: texture, commandBuffer: commandBuffer)
syphon.stop()
```

### Math Utilities

```swift
// Matrix creation
let model = float4x4(rotationY: angle) * float4x4(translation: position)
let view = float4x4(lookAt: eye, center: center, up: up)
let proj = float4x4(perspectiveFov: .pi/4, aspect: 16/9, near: 0.1, far: 100)

// Helpers
radians(90)              // degrees to radians
lerp(a, b, t)            // linear interpolation
smoothstep(0, 1, x)      // smooth interpolation
```

### Time Utilities

```swift
// Animation helpers
sine01(time, frequency: 1.0)      // 0...1 sine wave
triangle(time, frequency: 1.0)    // 0...1 triangle wave
sawtooth(time, frequency: 1.0)    // 0...1 sawtooth wave

// Frame timing
let timer = FrameTimer()
timer.update()           // call each frame
timer.elapsed            // total time
timer.deltaTime          // frame delta
timer.fps                // current FPS
```

---

## Syphon

Syphon allows real-time video sharing between applications. Compatible apps:

- [Syphon Recorder](https://github.com/Syphon/Recorder) - Record output
- [Simple Client](https://github.com/Syphon/Simple) - View output
- [Mad Mapper](https://madmapper.com/) - Projection mapping
- [Resolume](https://resolume.com/) - VJ software

---

## For Library Developers

This section is for those who want to contribute to metaphor itself.

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
make test       # Run tests
make clean      # Clean build artifacts
make check      # Check setup status
```


### How It Works

- **Local development**: When `Frameworks/Syphon.xcframework` exists, Package.swift uses the local path.
- **SPM users**: When the framework doesn't exist, Package.swift fetches the pre-built XCFramework from GitHub Releases.

### Release Process

1. Tag a new version:
   ```bash
   git tag v0.2.0
   git push --tags
   ```

2. GitHub Actions will automatically:
   - Build Syphon.xcframework
   - Create a GitHub Release with the XCFramework
   - Update Package.swift with the new URL and checksum
   - Commit the changes to main

---
