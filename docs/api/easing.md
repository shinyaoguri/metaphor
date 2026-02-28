# Easing

30 easing functions for smooth animations. Each takes a value `t` in [0, 1] and returns a curved value.

## Usage

### Direct Use

All easing functions have the signature `(Float) -> Float`:

```swift
let t = (time / duration)  // 0 to 1
let eased = easeOutCubic(t)
let x = lerp(startX, endX, eased)
```

### `ease(_ t: Float, from a: Float, to b: Float, using f: EasingFunction) -> Float`

Convenience function that combines easing with interpolation:

```swift
let x = ease(t, from: 0, to: 500, using: easeOutBounce)
```

## Easing Functions

### Quad (Power of 2)

| Function | Description |
|----------|-------------|
| `easeInQuad` | Slow start |
| `easeOutQuad` | Slow end |
| `easeInOutQuad` | Slow start and end |

### Cubic (Power of 3)

| Function | Description |
|----------|-------------|
| `easeInCubic` | Slow start, stronger |
| `easeOutCubic` | Slow end, stronger |
| `easeInOutCubic` | Slow start and end |

### Quart (Power of 4)

| Function | Description |
|----------|-------------|
| `easeInQuart` | Very slow start |
| `easeOutQuart` | Very slow end |
| `easeInOutQuart` | Very slow start and end |

### Quint (Power of 5)

| Function | Description |
|----------|-------------|
| `easeInQuint` | Extremely slow start |
| `easeOutQuint` | Extremely slow end |
| `easeInOutQuint` | Extremely slow start and end |

### Sine

| Function | Description |
|----------|-------------|
| `easeInSine` | Gentle sinusoidal start |
| `easeOutSine` | Gentle sinusoidal end |
| `easeInOutSine` | Gentle sinusoidal curve |

### Expo (Exponential)

| Function | Description |
|----------|-------------|
| `easeInExpo` | Near-zero start, then fast |
| `easeOutExpo` | Fast start, then near-zero end |
| `easeInOutExpo` | Both extremes |

### Circ (Circular)

| Function | Description |
|----------|-------------|
| `easeInCirc` | Circular curve start |
| `easeOutCirc` | Circular curve end |
| `easeInOutCirc` | Circular curve both |

### Back (Overshoot)

| Function | Description |
|----------|-------------|
| `easeInBack` | Pulls back before moving forward |
| `easeOutBack` | Overshoots then settles |
| `easeInOutBack` | Both |

### Elastic (Spring)

| Function | Description |
|----------|-------------|
| `easeInElastic` | Spring-like start |
| `easeOutElastic` | Spring-like settle |
| `easeInOutElastic` | Spring-like both |

### Bounce

| Function | Description |
|----------|-------------|
| `easeInBounce` | Bouncing start |
| `easeOutBounce` | Bouncing settle (like a ball dropping) |
| `easeInOutBounce` | Bouncing both |

## Example: Animated Circles

```swift
@main
final class EasingDemo: Sketch {
    let easings: [(String, EasingFunction)] = [
        ("easeInQuad", easeInQuad),
        ("easeOutCubic", easeOutCubic),
        ("easeInOutElastic", easeInOutElastic),
        ("easeOutBounce", easeOutBounce),
    ]

    func draw() {
        background(0.1)
        let cycle = time.truncatingRemainder(dividingBy: 3.0) / 3.0

        for (i, (name, fn)) in easings.enumerated() {
            let y = 100 + Float(i) * 80
            let x = ease(cycle, from: 100, to: width - 100, using: fn)

            fill(Color(hue: Float(i) * 0.2, saturation: 0.7, brightness: 1.0))
            circle(x, y, 20)

            fill(Color(gray: 0.6))
            textSize(12)
            text(name, 10, y + 5)
        }
    }
}
```

## See Also

- [Math](math.md) - lerp, smoothstep
- [Time & Animation](time.md) - Wave functions
