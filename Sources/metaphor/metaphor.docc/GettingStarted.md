# Getting Started with metaphor

Set up your first creative coding project with metaphor.

## Overview

metaphor is a Swift + Metal creative coding library. You create a sketch by implementing the
``MetaphorCore/Sketch`` protocol, and the library handles window creation, Metal setup, and the render loop.

## Requirements

| Requirement | Version |
|------------|---------|
| macOS | 14.0+ |
| Swift | 5.10+ |
| Xcode | 15.0+ |

## Installation

Add metaphor to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.2.1")
]
```

Then add it to your target's dependencies:

```swift
.executableTarget(
    name: "MySketch",
    dependencies: [
        .product(name: "metaphor", package: "metaphor")
    ]
)
```

## Creating Your First Sketch

Create a new Swift file and implement the ``MetaphorCore/Sketch`` protocol:

```swift
import metaphor

@main
final class MySketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720)
    }

    func setup() {
        
    }

    func draw() {
        background(0.1)

        // Draw a white circle at the center
        fill(Color.white)
        noStroke()
        circle(width / 2, height / 2, 200)
    }
}
```

Mark your sketch class with `@main` to make it the entry point of your application.

## The Sketch Lifecycle

The ``MetaphorCore/Sketch`` protocol provides callback methods that are called at specific points:

- `setup()` — Called once when the sketch starts. Use this to load resources and initialize state.
- `draw()` — Called every frame. This is where you put your drawing code.
- `compute()` — Called every frame before drawing. Use this for GPU compute dispatches.

## Configuration

Use ``MetaphorCore/SketchConfig`` to customize the sketch behavior. Override the `config` property
on your ``MetaphorCore/Sketch`` class:

```swift
var config: SketchConfig {
    SketchConfig(
        width: 1920,       // Offscreen texture width (default: 1920)
        height: 1080,      // Offscreen texture height (default: 1080)
        title: "My Sketch", // Window title (default: "metaphor")
        fps: 60,           // Target frame rate (default: 60)
        syphonName: nil,   // Syphon server name, nil to disable (default: nil)
        windowScale: 0.5,  // Window size = texture size * scale (default: 0.5)
        fullScreen: false,  // Launch in full-screen mode (default: false)
        renderLoopMode: .displayLink // .displayLink or .timer(fps:) (default: .displayLink)
    )
}
```

All parameters have defaults, so `SketchConfig()` alone gives you a 1920×1080 canvas at 60 fps.

You can also resize the canvas dynamically inside `setup()` using `createCanvas(width:height:)`:

```swift
func setup() {
    createCanvas(width: 800, height: 600)
}
```

### Built-in Properties

Every ``MetaphorCore/Sketch`` implementation has access to these properties:

| Property | Type | Description |
|----------|------|-------------|
| `width` | `Float` | Canvas width in pixels |
| `height` | `Float` | Canvas height in pixels |
| `frameCount` | `Int` | Number of frames rendered so far |
| `time` | `Float` | Elapsed seconds since sketch started |
| `deltaTime` | `Float` | Seconds since last frame |
| `mouseX` | `Float` | Current mouse X position |
| `mouseY` | `Float` | Current mouse Y position |
| `pmouseX` | `Float` | Mouse X position from the previous frame |
| `pmouseY` | `Float` | Mouse Y position from the previous frame |
| `isMousePressed` | `Bool` | Whether a mouse button is currently pressed |
| `mouseButton` | `Int` | Currently pressed mouse button (0=left, 1=right, 2=middle) |
| `isKeyPressed` | `Bool` | Whether a key is currently pressed |
| `key` | `Character?` | Last key that was pressed |
| `keyCode` | `UInt16?` | Key code of the last key pressed |

### Input Event Callbacks

Override these methods to respond to user input:

| Method | Description |
|--------|-------------|
| `mousePressed()` | Mouse button was pressed |
| `mouseReleased()` | Mouse button was released |
| `mouseMoved()` | Mouse was moved |
| `mouseDragged()` | Mouse was dragged |
| `mouseScrolled()` | Mouse scroll event |
| `mouseClicked()` | Mouse click (press + release without drag) |
| `keyPressed()` | Key was pressed |
| `keyReleased()` | Key was released |

## Drawing

```swift
@main
final class MySketch: Sketch {
    func draw() {
        background(0)
        fill(1, 0, 0)
        rect(100, 100, 200, 150)
    }
}
```

Drawing methods like `background()`, `fill()`, `rect()`, and `circle()` are available as
extensions on the ``MetaphorCore/Sketch`` protocol. They delegate to the underlying
``MetaphorCore/SketchContext``, which you can also access directly via the `context` property.

## Next Steps

- Explore 2D drawing with ``MetaphorCore/Canvas2D``
- Learn about 3D rendering with ``MetaphorCore/Canvas3D``
- Add post-processing effects with ``MetaphorCore/PostEffect``
- Set up Syphon output with ``MetaphorCore/SyphonOutput``
