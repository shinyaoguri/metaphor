# Color & Style

Functions for setting colors, fills, strokes, and blend modes.

## Color

The `Color` struct represents an RGBA color with values in the range 0.0 to 1.0.

### Constructors

```swift
// RGB (0.0 - 1.0)
Color(r: 1.0, g: 0.5, b: 0.0)
Color(r: 1.0, g: 0.5, b: 0.0, a: 0.8)

// Grayscale
Color(gray: 0.5)
Color(gray: 0.5, alpha: 0.8)

// HSB (hue: 0-1, saturation: 0-1, brightness: 0-1)
Color(hue: 0.6, saturation: 0.8, brightness: 1.0)

// Hex
Color(hex: 0xFF6600)
Color(hex: 0x80FF6600)     // With alpha
Color(hex: "#FF6600")      // String
Color(hex: "#80FF6600")    // String with alpha
```

### Named Colors

| Constant | Value |
|----------|-------|
| `Color.black` | (0, 0, 0) |
| `Color.white` | (1, 1, 1) |
| `Color.red` | (1, 0, 0) |
| `Color.green` | (0, 1, 0) |
| `Color.blue` | (0, 0, 1) |
| `Color.yellow` | (1, 1, 0) |
| `Color.cyan` | (0, 1, 1) |
| `Color.magenta` | (1, 0, 1) |
| `Color.orange` | (1, 0.65, 0) |
| `Color.clear` | (0, 0, 0, 0) |

### Methods

```swift
let c = Color.red
c.withAlpha(0.5)                   // Same color, 50% opacity
c.lerp(to: Color.blue, t: 0.5)    // Blend between two colors
```

## Background

### `background(_ color: Color)` / `background(_ gray: Float)`

Clears the canvas with a color. Call at the start of `draw()`.

```swift
background(Color.black)
background(0.1)  // Dark gray
```

## Fill

### `fill(_ color: Color)`

Sets the fill color for subsequent shapes.

```swift
fill(Color.red)
circle(100, 100, 50)

fill(Color(hue: 0.5, saturation: 0.8, brightness: 1.0))
rect(200, 200, 100, 100)
```

### `fill(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1.0)`

Sets fill color using RGBA components.

```swift
fill(1.0, 0.5, 0.0)       // Orange, full opacity
fill(1.0, 0.5, 0.0, 0.5)  // Orange, 50% opacity
```

### `noFill()`

Disables filling. Only the stroke will be drawn.

```swift
noFill()
stroke(Color.white)
circle(100, 100, 80)  // Outline only
```

## Stroke

### `stroke(_ color: Color)`

Sets the stroke (outline) color.

```swift
stroke(Color.yellow)
line(0, 0, width, height)
```

### `stroke(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1.0)`

Sets stroke color using RGBA components.

### `noStroke()`

Disables the stroke.

```swift
noStroke()
fill(Color.blue)
rect(100, 100, 200, 200)  // No outline
```

### `strokeWeight(_ weight: Float)`

Sets the stroke thickness in pixels.

```swift
strokeWeight(4)
stroke(Color.white)
line(100, 100, 500, 500)
```

## Blend Modes

### `blendMode(_ mode: BlendMode)`

Sets the blending mode for subsequent drawing operations.

| Mode | Description |
|------|-------------|
| `.opaque` | No blending (fully replaces pixels) |
| `.alpha` | Standard alpha blending (default) |
| `.additive` | Adds colors together (glow effect) |
| `.multiply` | Multiplies colors (darkening) |
| `.screen` | Screen blend (brightening) |
| `.subtract` | Subtracts source from destination |
| `.lightest` | Keeps the brighter pixel |
| `.darkest` | Keeps the darker pixel |

```swift
// Glow effect
blendMode(.additive)
fill(Color(r: 0.2, g: 0.5, b: 1.0, a: 0.3))
for i in 0..<20 {
    circle(width / 2, height / 2, Float(i) * 20)
}
blendMode(.alpha)  // Reset to default
```

## See Also

- [2D Shapes](shapes-2d.md)
- [Lighting](lighting.md) - 3D color via lights
- [Material & Texture](material.md) - Surface appearance
