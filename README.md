# metaphor

Swift + Metal creative coding library inspired by Processing / p5.js / openFrameworks.

## Requirements

- macOS 14.0+ / iOS 17.0+
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

Or in Xcode: File -> Add Package Dependencies -> enter the repository URL.

---

## Quick Start

### Sketch Protocol (Recommended)

The simplest way to get started. `import metaphor` gives you Processing-like global functions:

```swift
import metaphor

@main
final class MySketch: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "My Sketch", width: 1920, height: 1080)
    }

    func setup() {
        // One-time initialization
    }

    func draw() {
        background(.black)
        fill(.white)
        circle(width / 2, height / 2, 200)
    }
}
```

### Minimal Project Setup

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

Build and run:

```bash
swift build && swift run
```

---

## Features

### 2D Drawing

```swift
func draw() {
    background(.black)
    fill(.red)
    stroke(.white)
    strokeWeight(2)
    circle(width / 2, height / 2, 200)
    rect(100, 100, 300, 200)
}
```

### 3D Drawing

```swift
func draw() {
    background(.black)
    lights()
    orbitControl()

    fill(.blue)
    push()
    translate(0, 0, 0)
    rotateY(frameCount * 0.01)
    box(100)
    pop()
}
```

### Audio Analysis

```swift
let analyzer = AudioAnalyzer(fftSize: 1024)
analyzer.start()
analyzer.update()

let volume = analyzer.volume
let spectrum = analyzer.spectrum
let isBeat = analyzer.isBeat
```

### OSC / MIDI

```swift
let osc = OSCReceiver(port: 9000)
osc.on("/control") { values in
    // Handle OSC messages
}
osc.start()

let midi = MIDIManager()
midi.start()
let cc = midi.controllerValue(1)
```

### 2D Physics

```swift
let world = Physics2D(cellSize: 50)
world.addGravity(0, 980)
let ball = world.addCircle(x: 100, y: 100, radius: 20)
world.step(1.0 / 60.0)
```

### Plugin System

Extend the render loop with custom plugins:

```swift
class MyPlugin: MetaphorPlugin {
    var pluginID: String { "my-plugin" }

    func onAfterRender(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        // Process rendered frame
    }
}

renderer.addPlugin(MyPlugin())
```

### More Features

- **GPU Compute**: ComputeKernel, GPUBuffer for general-purpose GPU programming
- **Post-Processing**: Built-in effects (bloom, blur, chromatic aberration, etc.) and custom shaders
- **Particle System**: GPU-accelerated particle simulation with instanced rendering
- **Syphon Output**: Real-time video sharing to VJ software (macOS only)
- **Core Image**: Zero-copy CIFilter integration with 30+ presets
- **MPS Ray Tracing**: Ambient occlusion, shadow, diffuse via Metal Performance Shaders
- **Noise**: 8 noise types via GameplayKit (Perlin, simplex, Voronoi, etc.)
- **Export**: H.264 video, GIF, and frame sequence export
- **Tweens**: 30 easing functions with chainable animations

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
make test       # Run tests (~500 tests across 4 test targets)
make clean      # Clean build artifacts
make check      # Check setup status
make docs       # Build DocC documentation
```

### Project Structure

```
Sources/
  MetaphorCore/       Core rendering engine (Metal, 2D/3D drawing, shaders, etc.)
  MetaphorAudio/      Standalone audio module (FFT, beat detection, playback)
  MetaphorNetwork/    Standalone network module (OSC, MIDI)
  MetaphorPhysics/    Standalone physics module (2D Verlet, spatial hashing)
  metaphor/           Umbrella target (re-exports + bridge extensions)

Tests/
  metaphorTests/          Core integration tests
  MetaphorAudioTests/     Audio module tests
  MetaphorNetworkTests/   Network module tests
  MetaphorPhysicsTests/   Physics module tests
```

### How Syphon Works

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
