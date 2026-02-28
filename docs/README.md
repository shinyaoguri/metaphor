<div class="hero-section">
  <h1>metaphor</h1>
  <p class="tagline">A creative coding library for Swift + Metal</p>
  <div class="badges">
    <img src="https://img.shields.io/badge/platform-macOS_14+-blue?style=flat-square" alt="macOS 14+">
    <img src="https://img.shields.io/badge/swift-6.0+-orange?style=flat-square" alt="Swift 6.0+">
    <img src="https://img.shields.io/badge/Metal-GPU_Accelerated-purple?style=flat-square" alt="Metal">
  </div>
</div>

**metaphor** is a creative coding framework for Swift, inspired by [p5.js](https://p5js.org/) and [Processing](https://processing.org/). It uses Metal for GPU-accelerated 2D/3D rendering on macOS.

Write a few lines of Swift, and get a window with real-time graphics.

## Quick Start

```bash
mkdir MySketch && cd MySketch
swift package init --type executable
```

Add metaphor to `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MySketch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.1.0")
    ],
    targets: [
        .executableTarget(name: "MySketch", dependencies: ["metaphor"])
    ]
)
```

Write `Sources/main.swift`:

```swift
import metaphor

@main
final class MySketch: Sketch {
    func draw() {
        background(0.1)
        fill(Color(hue: time * 0.1, saturation: 0.8, brightness: 1.0))
        circle(width / 2, height / 2, 200)
    }
}
```

```bash
swift build && swift run
```

## Features

<div class="features">
  <div class="feature">
    <h3>2D Drawing</h3>
    <p>Rectangles, circles, lines, triangles, polygons, bezier curves, arcs, and custom shapes with beginShape/endShape.</p>
  </div>
  <div class="feature">
    <h3>3D Primitives</h3>
    <p>Box, sphere, cylinder, cone, torus, plane, and custom meshes with full transform stack.</p>
  </div>
  <div class="feature">
    <h3>Lighting & Materials</h3>
    <p>Directional, point, and spot lights. Blinn-Phong specular, emissive, and metallic materials.</p>
  </div>
  <div class="feature">
    <h3>GPU Compute</h3>
    <p>Write Metal compute shaders inline. GPUBuffer for typed data. Perfect for particle simulations.</p>
  </div>
  <div class="feature">
    <h3>Color & Style</h3>
    <p>RGB, HSB, and hex colors. 8 blend modes. Fill, stroke, and transparency.</p>
  </div>
  <div class="feature">
    <h3>Math & Animation</h3>
    <p>Perlin noise, 30 easing functions, wave generators, lerp, smoothstep, and matrix math.</p>
  </div>
  <div class="feature">
    <h3>Input</h3>
    <p>Mouse position, clicks, drags, and keyboard events with simple callback methods.</p>
  </div>
  <div class="feature">
    <h3>Syphon Output</h3>
    <p>Stream your visuals to VJ software like Resolume, VDMX, or MadMapper in real time.</p>
  </div>
</div>

## Installation

Add metaphor to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.1.0")
]
```

See the [Getting Started](getting-started.md) guide for detailed setup instructions.
