# Getting Started

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode 15.0+

## Step 0: Install Swift

If you don't have Swift installed yet, you need Xcode (which includes Swift).

### Install Xcode

1. Open the **App Store** on your Mac
2. Search for **Xcode** and install it
3. Open Xcode once to accept the license agreement

### Verify installation

Open **Terminal** (Applications → Utilities → Terminal) and run:

```bash
swift --version
```

You should see something like:

```
swift-driver version: 1.x.x Apple Swift version 6.x
```

> If you prefer not to install the full Xcode, you can use [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/) by running `xcode-select --install`. However, full Xcode is recommended for Metal development.

## Step 1: Create a project

Open Terminal and create a new Swift package:

```bash
mkdir MySketch
cd MySketch
swift package init --type executable
```

This creates a project with the following structure:

```
MySketch/
├── Package.swift
└── Sources/
    └── main.swift
```

## Step 2: Add metaphor dependency

Open `Package.swift` in a text editor and replace its contents with:

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

Key points:
- `platforms: [.macOS(.v14)]` — metaphor requires macOS 14 (Sonoma) or later
- `dependencies` — pulls metaphor from GitHub via Swift Package Manager

## Step 3: Write your first sketch

Open `Sources/main.swift` and replace its contents with:

```swift
import metaphor

@main
final class MySketch: Sketch {
    func draw() {
        background(0.1)

        // Draw a white circle orbiting the center
        let x = width / 2 + cos(time) * 100
        let y = height / 2 + sin(time) * 100

        fill(Color.white)
        circle(x, y, 50)
    }
}
```

What this does:
- `@main` — marks this class as the app entry point
- `Sketch` — the metaphor protocol that gives you a window and draw loop
- `draw()` — called every frame (60 fps by default)
- `background(0.1)` — clears the screen with dark gray
- `width`, `height`, `time` — built-in properties
- `fill()`, `circle()` — drawing functions (like p5.js)

## Step 4: Build and run

```bash
swift build && swift run
```

The first build takes a minute or two to download and compile dependencies. After that, a window appears with a white circle orbiting the center of the screen.

> **Tip**: Press `Ctrl+C` in Terminal to quit the app.

## Step 5: Experiment

Try changing the code and see what happens:

```swift
import metaphor

@main
final class MySketch: Sketch {
    func draw() {
        background(0.05)

        for i in 0..<10 {
            let t = Float(i) / 10.0
            let angle = time + t * Float.pi * 2
            let x = width / 2 + cos(angle) * (50 + t * 150)
            let y = height / 2 + sin(angle) * (50 + t * 150)

            fill(Color(hue: t, saturation: 0.8, brightness: 1.0))
            circle(x, y, 20)
        }
    }
}
```

Rebuild and run:

```bash
swift build && swift run
```

---

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

- [2D Shapes](api/shapes-2d.md) — Rectangles, circles, lines, and more
- [Color & Style](api/color.md) — Colors, fills, strokes, blend modes
- [3D Shapes](api/shapes-3d.md) — 3D primitives and meshes
- [Examples](examples.md) — 27 example projects to explore
