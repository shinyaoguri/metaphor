# Math

Mathematical utilities for creative coding.

## Angle Conversion

### `radians(_ degrees: Float) -> Float`

Converts degrees to radians.

```swift
let r = radians(90)   // Float.pi / 2
let r2 = radians(360) // Float.pi * 2
```

### `degrees(_ radians: Float) -> Float`

Converts radians to degrees.

```swift
let d = degrees(Float.pi)  // 180.0
```

## Interpolation

### `lerp<T>(_ a: T, _ b: T, _ t: T) -> T`

Linear interpolation between two values. Works with `Float`, `SIMD2<Float>`, `SIMD3<Float>`, and `SIMD4<Float>`.

```swift
let v = lerp(0.0, 100.0, 0.5)  // 50.0

let pos = lerp(
    SIMD3<Float>(0, 0, 0),
    SIMD3<Float>(100, 200, 300),
    0.25
)
```

### `saturate(_ x: Float) -> Float`

Clamps a value to the range [0, 1].

```swift
saturate(-0.5)  // 0.0
saturate(0.7)   // 0.7
saturate(1.5)   // 1.0
```

### `smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float`

Hermite interpolation. Returns 0 below `edge0`, 1 above `edge1`, and a smooth curve between.

```swift
let t = smoothstep(0, 100, 50)  // ~0.5 (smooth)
```

## Matrix Constructors (float4x4)

For advanced use or custom rendering:

| Constructor | Description |
|-------------|-------------|
| `float4x4(rotationX:)` | Rotation around X axis |
| `float4x4(rotationY:)` | Rotation around Y axis |
| `float4x4(rotationZ:)` | Rotation around Z axis |
| `float4x4(translation:)` | Translation matrix |
| `float4x4(scale:)` | Scale matrix (SIMD3 or uniform Float) |
| `float4x4(lookAt:center:up:)` | View matrix |
| `float4x4(perspectiveFov:aspect:near:far:)` | Perspective projection |
| `float4x4(orthographic:right:bottom:top:near:far:)` | Orthographic projection |
| `float4x4.identity` | Identity matrix |

```swift
let model = float4x4(translation: SIMD3(100, 0, 0))
    * float4x4(rotationY: time)
    * float4x4(scale: 2.0)
```

## See Also

- [Noise](noise.md) - Perlin noise
- [Easing](easing.md) - Easing functions
- [Time & Animation](time.md) - Wave functions
