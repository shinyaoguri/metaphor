# Getting Started

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode 15.0+

## Installation

### 1. Create a new Swift package

```bash
mkdir MySketch && cd MySketch
swift package init --type executable
```

### 2. Add metaphor dependency

Edit `Package.swift`:

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
        .executableTarget(
            name: "MySketch",
            dependencies: ["metaphor"]
        )
    ]
)
```

### 3. Write your first sketch

Replace `Sources/main.swift` with:

```swift
import metaphor

@main
final class MySketch: Sketch {
    func draw() {
        background(0.1)

        // Rotating circle
        let x = width / 2 + cos(time) * 100
        let y = height / 2 + sin(time) * 100

        fill(Color.white)
        circle(x, y, 50)
    }
}
```

### 4. Build and run

```bash
swift build && swift run
```

A window appears with a white circle orbiting the center.

## Sketch Lifecycle

The `Sketch` protocol provides a p5.js-style lifecycle:

```swift
@main
final class MySketch: Sketch {
    // Optional: configure window size, title, FPS
    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "My App", fps: 60)
    }

    // Called once at startup
    func setup() {
        // Initialize state
    }

    // Called every frame
    func draw() {
        background(0.0)
        // Draw your visuals
    }

    // Optional: GPU compute before draw
    func compute() {
        // Run compute shaders
    }
}
```

## SketchConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `width` | `Int` | `1920` | Render texture width (pixels) |
| `height` | `Int` | `1080` | Render texture height (pixels) |
| `title` | `String` | `"metaphor"` | Window title |
| `fps` | `Int` | `60` | Target frame rate |
| `syphonName` | `String?` | `nil` | Syphon server name (nil = disabled) |
| `windowScale` | `Float` | `0.5` | Window size = texture size x scale |

## Built-in Properties

These are available inside any `Sketch` method:

| Property | Type | Description |
|----------|------|-------------|
| `width` | `Float` | Canvas width in pixels |
| `height` | `Float` | Canvas height in pixels |
| `time` | `Float` | Elapsed time in seconds |
| `deltaTime` | `Float` | Time since last frame |
| `frameCount` | `Int` | Current frame number |
| `input` | `InputManager` | Mouse & keyboard state |

## Two Drawing Styles

You can use either style (or mix them):

```swift
// Style A: implicit context (recommended)
func draw() {
    background(.black)
    fill(.white)
    circle(width / 2, height / 2, 200)
}

// Style B: explicit context
func draw(_ ctx: SketchContext) {
    ctx.background(.black)
    ctx.fill(.white)
    ctx.circle(ctx.width / 2, ctx.height / 2, 200)
}
```

## Next Steps

- [2D Shapes](api/shapes-2d.md) - Rectangles, circles, lines, and more
- [Color & Style](api/color.md) - Colors, fills, strokes, blend modes
- [3D Shapes](api/shapes-3d.md) - 3D primitives and meshes
- [Examples](examples.md) - 27 example projects to explore
