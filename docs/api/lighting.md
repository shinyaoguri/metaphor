# Lighting

Functions for adding light sources to 3D scenes. Supports up to 8 lights simultaneously.

## Quick Setup

### `lights()`

Adds default lighting (one directional light from the upper-right). Useful for quick prototyping.

```swift
lights()
fill(Color.white)
sphere(100)
```

### `noLights()`

Disables all lighting. Shapes will use flat fill colors.

```swift
noLights()
```

## Directional Light

### `directionalLight(_ x: Float, _ y: Float, _ z: Float)`

Adds a directional light (like the sun). The vector (x, y, z) points in the light's direction.

```swift
directionalLight(-1, -1, -1)  // Light from upper-right-front
```

### `directionalLight(_ x: Float, _ y: Float, _ z: Float, color: Color)`

Directional light with a custom color.

```swift
directionalLight(-1, -1, 0, color: Color(r: 1, g: 0.9, b: 0.8))
```

## Point Light

### `pointLight(_ x: Float, _ y: Float, _ z: Float, color: Color = .white, falloff: Float = 0.1)`

Adds a point light that emits in all directions from a position.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `x, y, z` | - | Light position in world space |
| `color` | `.white` | Light color |
| `falloff` | `0.1` | Attenuation factor (higher = faster falloff) |

```swift
pointLight(0, 200, 0, color: Color.yellow, falloff: 0.05)
```

## Spot Light

### `spotLight(_ x:_ y:_ z:_ dirX:_ dirY:_ dirZ: angle: falloff: color:)`

Adds a spot light with a cone of illumination.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `x, y, z` | - | Light position |
| `dirX, dirY, dirZ` | - | Direction the light points |
| `angle` | `Float.pi / 6` | Cone half-angle (~30 degrees) |
| `falloff` | `0.01` | Attenuation factor |
| `color` | `.white` | Light color |

```swift
spotLight(
    0, 300, 0,       // Position: above
    0, -1, 0,        // Direction: pointing down
    angle: Float.pi / 4,
    color: Color.cyan
)
```

## Ambient Light

### `ambientLight(_ strength: Float)`

Adds ambient (non-directional) illumination with a uniform brightness.

```swift
ambientLight(0.2)  // Subtle fill light
```

### `ambientLight(_ r: Float, _ g: Float, _ b: Float)`

Adds ambient light with a specific color.

```swift
ambientLight(0.1, 0.05, 0.15)  // Slight purple ambient
```

## Example: Multi-Light Scene

```swift
func draw() {
    background(0.05)
    camera(eye: SIMD3(0, 200, 400), center: SIMD3(0, 0, 0))
    perspective()

    // Ambient fill
    ambientLight(0.1)

    // Key light (warm)
    directionalLight(-1, -1, -0.5, color: Color(r: 1, g: 0.95, b: 0.9))

    // Orbiting point light (blue)
    let lx = cos(time) * 200
    let lz = sin(time) * 200
    pointLight(lx, 100, lz, color: Color.cyan, falloff: 0.02)

    // Scene
    fill(Color.white)
    sphere(80)

    fill(Color(gray: 0.5))
    pushMatrix()
    translate(0, -80, 0)
    plane(400, 400)
    popMatrix()
}
```

## See Also

- [Material & Texture](material.md) - Specular, emissive, metallic
- [Camera](camera.md) - Camera setup
- [3D Shapes](shapes-3d.md) - 3D primitives
