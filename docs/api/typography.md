# Typography

Functions for rendering text on screen.

## Drawing Text

### `text(_ string: String, _ x: Float, _ y: Float)`

Draws a text string at the given position. Uses the current fill color.

```swift
fill(Color.white)
text("Hello, world!", 100, 100)
```

## Text Style

### `textSize(_ size: Float)`

Sets the font size in points.

```swift
textSize(32)
text("Large text", 100, 100)

textSize(12)
text("Small text", 100, 200)
```

### `textFont(_ family: String)`

Sets the font family by name.

```swift
textFont("Menlo")
text("Monospace", 100, 100)

textFont("Helvetica Neue")
text("Sans-serif", 100, 150)
```

### `textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline)`

Sets text alignment.

**Horizontal alignment (`TextAlignH`):**

| Value | Description |
|-------|-------------|
| `.left` | Left-aligned (default) |
| `.center` | Center-aligned |
| `.right` | Right-aligned |

**Vertical alignment (`TextAlignV`):**

| Value | Description |
|-------|-------------|
| `.baseline` | Baseline (default) |
| `.top` | Top of text |
| `.center` | Vertical center |
| `.bottom` | Bottom of text |

```swift
textAlign(.center, .center)
textSize(48)
fill(Color.white)
text("Centered", width / 2, height / 2)
```

## Example: HUD Display

```swift
func draw() {
    background(0.1)

    // Draw some content...

    // HUD overlay
    textFont("Menlo")
    textSize(14)
    fill(Color(gray: 1.0, alpha: 0.7))
    textAlign(.left, .top)
    text("FPS: \(Int(1.0 / deltaTime))", 10, 10)
    text("Frame: \(frameCount)", 10, 30)
    text("Time: \(String(format: "%.1f", time))s", 10, 50)
}
```

## See Also

- [Color & Style](color.md) - Fill color for text
- [Image](image.md) - Drawing images
