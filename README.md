# metaphor

Swift + Metal creative coding library with Syphon output support.

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 6.0+

## Setup

```bash
# Clone with submodules
git clone --recursive https://github.com/shinyaoguri/metaphor.git
cd metaphor

# Build Syphon.xcframework
make setup

# Build the library
make build
```

## Usage

### Basic Example

```swift
import SwiftUI
import metaphor

@main
struct MyApp: App {
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

        // Start Syphon server
        renderer.startSyphonServer(name: "MyApp")

        // Set draw callback
        renderer.onDraw = { encoder, time in
            // Your Metal rendering code here
        }

        self.renderer = renderer
    }
}
```

### Adding as Dependency

```swift
// Package.swift
dependencies: [
    .package(path: "/path/to/metaphor"),
]
```

Note: Users must run `make setup` in the metaphor directory first to build Syphon.xcframework.

## Components

### MetaphorRenderer

Main renderer class that manages Metal device, command queue, and Syphon output.

```swift
let renderer = MetaphorRenderer(
    width: 1920,      // Offscreen texture width
    height: 1080,     // Offscreen texture height
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

## Examples

### RotatingCube

3D rotating cube with per-face colors and lighting.

```bash
cd Examples/RotatingCube
swift build && swift run
```

### Particles

100,000 particles with compute shader physics and additive blending.

```bash
cd Examples/Particles
swift build && swift run
```

## Syphon

Syphon allows real-time video sharing between applications. Use apps like:

- [Syphon Recorder](https://github.com/Syphon/Recorder) - Record output
- [Simple Client](https://github.com/Syphon/Simple) - View output
- [Mad Mapper](https://madmapper.com/) - Projection mapping
- [Resolume](https://resolume.com/) - VJ software

## Makefile Commands

```bash
make setup      # Initialize submodules + build Syphon
make build      # Build the Swift package
make test       # Run tests
make clean      # Clean build artifacts
make check      # Check setup status
make help       # Show all commands
```

## License

MIT License
