# Sketch

The core protocol for creating creative coding sketches. Implement this protocol with `@main` to get an automatic window, renderer, and draw loop.

## Basic Usage

```swift
import metaphor

@main
final class MySketch: Sketch {
    func setup() {
        // Called once
    }

    func draw() {
        background(0.1)
        fill(Color.white)
        circle(width / 2, height / 2, 100)
    }
}
```

## Lifecycle Methods

### `setup()`

Called once after the window and renderer are initialized. Use this to set initial state.

```swift
func setup() {
    // Load images, create buffers, initialize variables
}
```

### `draw()` / `draw(_ ctx: SketchContext)`

Called every frame. All drawing happens here.

```swift
// Implicit context (call drawing functions directly)
func draw() {
    background(.black)
    circle(100, 100, 50)
}

// Explicit context
func draw(_ ctx: SketchContext) {
    ctx.background(.black)
    ctx.circle(100, 100, 50)
}
```

### `compute()`

Called every frame before `draw()`. Use for GPU compute shader dispatch.

```swift
func compute() {
    dispatch(kernel, threads: count) { encoder in
        encoder.setBuffer(buffer.buffer, offset: 0, index: 0)
    }
}
```

## Configuration

### `config: SketchConfig`

Override to customize the sketch window and rendering:

```swift
var config: SketchConfig {
    SketchConfig(
        width: 1920,        // Texture width (default: 1920)
        height: 1080,       // Texture height (default: 1080)
        title: "My Sketch", // Window title (default: "metaphor")
        fps: 60,            // Frame rate (default: 60)
        syphonName: nil,    // Syphon server name (default: nil)
        windowScale: 0.5    // Window = texture * scale (default: 0.5)
    )
}
```

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `width` | `Float` | Canvas width in pixels |
| `height` | `Float` | Canvas height in pixels |
| `time` | `Float` | Seconds since launch |
| `deltaTime` | `Float` | Seconds since last frame |
| `frameCount` | `Int` | Frame counter (starts at 0) |
| `input` | `InputManager` | Mouse and keyboard state |

## Input Events

All input event methods are optional:

```swift
func mousePressed()   // Mouse button pressed
func mouseReleased()  // Mouse button released
func mouseMoved()     // Mouse moved (no button)
func mouseDragged()   // Mouse moved while pressed
func keyPressed()     // Key pressed
func keyReleased()    // Key released
```

See [Input](input.md) for details.

## See Also

- [Getting Started](getting-started.md)
- [Color & Style](color.md)
- [2D Shapes](shapes-2d.md)
