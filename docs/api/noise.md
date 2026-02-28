# Noise

Perlin noise for procedural generation. Returns smooth, continuous random values.

## Global Functions

### `noise(_ x: Float) -> Float`

1D Perlin noise. Returns a value in approximately [0, 1].

```swift
let n = noise(time)
```

### `noise(_ x: Float, _ y: Float) -> Float`

2D Perlin noise. Useful for terrain, textures, and flow fields.

```swift
for x in stride(from: 0, to: width, by: 10) {
    for y in stride(from: 0, to: height, by: 10) {
        let n = noise(x * 0.01, y * 0.01)
        fill(Color(gray: n))
        rect(x, y, 10, 10)
    }
}
```

### `noise(_ x: Float, _ y: Float, _ z: Float) -> Float`

3D Perlin noise. Use the third dimension for animation:

```swift
let n = noise(x * 0.01, y * 0.01, time * 0.5)
```

## Configuration

### `noiseDetail(octaves: Int = 4, falloff: Float = 0.5)`

Controls noise complexity. More octaves add finer detail; falloff controls how much each octave contributes.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `octaves` | `4` | Number of noise layers |
| `falloff` | `0.5` | Amplitude multiplier per octave (0-1) |

```swift
noiseDetail(octaves: 8, falloff: 0.65)  // More detail
noiseDetail(octaves: 1)                  // Smooth, simple
```

### `noiseSeed(_ seed: UInt64)`

Sets the noise seed for reproducible results.

```swift
noiseSeed(42)
```

## NoiseGenerator Struct

For multiple independent noise sources:

```swift
let noiseA = NoiseGenerator(seed: 0)
let noiseB = NoiseGenerator(seed: 123)

let a = noiseA.noise(time)
let b = noiseB.noise(time)  // Different sequence
```

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `octaves` | `Int` | `4` | Number of octaves |
| `falloff` | `Float` | `0.5` | Octave falloff |

## Example: Flow Field

```swift
func draw() {
    background(0.05)
    stroke(Color(gray: 1.0, alpha: 0.3))
    strokeWeight(1)

    let scale: Float = 0.005
    for x in stride(from: 0, to: width, by: 15) {
        for y in stride(from: 0, to: height, by: 15) {
            let angle = noise(x * scale, y * scale, time * 0.3) * Float.pi * 4
            let len: Float = 12
            line(x, y, x + cos(angle) * len, y + sin(angle) * len)
        }
    }
}
```

## See Also

- [Math](math.md) - lerp, smoothstep
- [Easing](easing.md) - Easing curves
