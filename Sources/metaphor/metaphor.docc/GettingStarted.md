# Getting Started with metaphor

Set up your first creative coding project with metaphor.

## Overview

metaphor is a Swift + Metal creative coding library. You create a sketch by implementing the
``Sketch`` protocol, and the library handles window creation, Metal setup, and the render loop.

## Requirements

| Requirement | Version |
|------------|---------|
| macOS | 14.0+ |
| iOS | 17.0+ |
| Swift | 6.0+ |
| Xcode | 15.0+ |

## Installation

Add metaphor to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.1.0")
]
```

Then add it to your target's dependencies:

```swift
.target(
    name: "MySketch",
    dependencies: ["metaphor"]
)
```

## Creating Your First Sketch

Create a new Swift file and implement the ``Sketch`` protocol:

```swift
import metaphor

@main
final class MySketch: Sketch {
    func setup() {
        size(1280, 720)
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

The ``Sketch`` protocol provides callback methods that are called at specific points:

- ``Sketch/setup()`` — Called once when the sketch starts. Use this to configure canvas size,
  load resources, and initialize state.
- ``Sketch/draw()`` — Called every frame. This is where you put your drawing code.

## Configuration

Use ``SketchConfig`` to customize the sketch behavior:

```swift
func setup() {
    size(1920, 1080)
}
```

### Built-in Properties

Every ``Sketch`` implementation has access to these properties:

| Property | Type | Description |
|----------|------|-------------|
| `width` | `Float` | Canvas width in pixels |
| `height` | `Float` | Canvas height in pixels |
| `frameCount` | `Int` | Number of frames drawn |
| `mouseX` | `Float` | Current mouse X position |
| `mouseY` | `Float` | Current mouse Y position |
| `elapsedTime` | `Double` | Seconds since sketch started |
| `deltaTime` | `Double` | Seconds since last frame |

## Drawing Styles

metaphor supports two drawing patterns:

### Style 1: Direct Drawing

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

### Style 2: Using the Context

```swift
@main
final class MySketch: Sketch {
    func draw(_ ctx: SketchContext) {
        ctx.background(0)
        ctx.fill(1, 0, 0)
        ctx.rect(100, 100, 200, 150)
    }
}
```

Both styles are equivalent. The direct style uses the active sketch context implicitly.

## Next Steps

- Explore 2D drawing with ``Canvas2D``
- Learn about 3D rendering with ``Canvas3D``
- Add post-processing effects with ``PostEffect``
- Set up Syphon output with ``SyphonOutput``
