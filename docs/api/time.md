# Time & Animation

Utilities for time-based animation.

## Built-in Properties

These are available in any `Sketch`:

| Property | Type | Description |
|----------|------|-------------|
| `time` | `Float` | Seconds since launch |
| `deltaTime` | `Float` | Seconds since last frame |
| `frameCount` | `Int` | Frame counter |

```swift
func draw() {
    let x = width / 2 + cos(time) * 100
    circle(x, height / 2, 50)
}
```

## Wave Functions

Oscillating functions that take time and frequency, returning values in [0, 1].

### `sine01(_ time: Double, frequency: Double = 1.0) -> Float`

Smooth sine wave oscillation between 0 and 1.

```swift
let brightness = sine01(Double(time), frequency: 2.0)
fill(Color(gray: brightness))
```

### `cosine01(_ time: Double, frequency: Double = 1.0) -> Float`

Cosine wave (starts at 1, sine01 starts at 0.5).

### `triangle(_ time: Double, frequency: Double = 1.0) -> Float`

Linear triangle wave. Ramps up then down linearly.

```swift
let t = triangle(Double(time), frequency: 0.5)
let x = lerp(100.0, Float(width) - 100, t)
circle(x, height / 2, 30)
```

### `sawtooth(_ time: Double, frequency: Double = 1.0) -> Float`

Linear ramp from 0 to 1, then resets.

```swift
let progress = sawtooth(Double(time), frequency: 0.3)
rect(0, 0, width * progress, 10)
```

### `square(_ time: Double, frequency: Double = 1.0, duty: Double = 0.5) -> Float`

Square wave — alternates between 0 and 1.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `time` | - | Current time |
| `frequency` | `1.0` | Oscillation frequency (Hz) |
| `duty` | `0.5` | Fraction of period spent at 1.0 |

```swift
let on = square(Double(time), frequency: 2.0)
if on > 0 {
    fill(Color.white)
} else {
    fill(Color.black)
}
```

## FrameTimer

A class for manual time tracking (used internally by MetaphorRenderer, but also available for custom use):

```swift
let timer = FrameTimer()

// Call each frame
timer.update()

timer.elapsed     // Total seconds (Double)
timer.deltaTime   // Frame delta (Double)
timer.fps         // Current FPS (Double)
timer.totalFrames // Frame count (UInt64)

timer.reset()     // Reset to zero
```

## Example: Pulsing Animation

```swift
func draw() {
    background(0.1)

    // Smooth pulse
    let pulse = sine01(Double(time), frequency: 1.0)
    let size = lerp(50.0, 200.0, pulse)

    fill(Color(hue: Float(sawtooth(Double(time), frequency: 0.1)),
               saturation: 0.8,
               brightness: 1.0))
    circle(width / 2, height / 2, size)
}
```

## See Also

- [Easing](easing.md) - Non-linear interpolation
- [Math](math.md) - lerp, smoothstep
- [Noise](noise.md) - Procedural randomness
