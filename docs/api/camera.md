# Camera

Functions for setting up 3D camera and projection.

## Camera Position

### `camera(eye:center:up:)`

Sets the camera using SIMD3 vectors.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `eye` | `SIMD3<Float>` | - | Camera position |
| `center` | `SIMD3<Float>` | - | Look-at target |
| `up` | `SIMD3<Float>` | `(0, 1, 0)` | Up direction |

```swift
camera(
    eye: SIMD3(0, 200, 500),
    center: SIMD3(0, 0, 0)
)
```

### `camera(_ eyeX:_ eyeY:_ eyeZ:_ centerX:_ centerY:_ centerZ:_ upX:_ upY:_ upZ:)`

Sets the camera using individual float values (p5.js style).

```swift
camera(0, 200, 500, 0, 0, 0, 0, 1, 0)
```

## Projection

### `perspective(fov:near:far:)`

Sets a perspective projection.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `fov` | `Float.pi / 3` | Field of view in radians (~60 degrees) |
| `near` | `0.1` | Near clipping plane |
| `far` | `10000` | Far clipping plane |

```swift
perspective()                           // Default
perspective(fov: Float.pi / 4)          // Narrower FOV
perspective(fov: Float.pi / 2, near: 1) // Wide angle
```

## Example: Orbiting Camera

```swift
func draw() {
    background(0.1)

    // Orbit around the scene
    let radius: Float = 500
    let camX = cos(time * 0.5) * radius
    let camZ = sin(time * 0.5) * radius
    camera(eye: SIMD3(camX, 200, camZ), center: SIMD3(0, 0, 0))
    perspective()
    lights()

    fill(Color.white)
    box(100)
}
```

## See Also

- [3D Shapes](shapes-3d.md)
- [Lighting](lighting.md)
- [Transform](transform.md) - 3D transforms
