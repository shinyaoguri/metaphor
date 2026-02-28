# 3D Shapes

GPU-accelerated 3D primitives rendered with Metal. Use with [Camera](camera.md), [Lighting](lighting.md), and [Material](material.md) for full 3D scenes.

## Box

### `box(_ width: Float, _ height: Float, _ depth: Float)`

Draws a box (rectangular prism) at the current transform position.

```swift
box(100, 200, 50)
```

### `box(_ size: Float)`

Draws a cube with equal dimensions.

```swift
box(100)
```

## Sphere

### `sphere(_ radius: Float, detail: Int = 24)`

Draws a UV sphere. The `detail` parameter controls tessellation.

| Parameter | Description |
|-----------|-------------|
| `radius` | Sphere radius |
| `detail` | Number of segments (default: 24) |

```swift
sphere(50)
sphere(100, detail: 48)  // Higher quality
```

## Cylinder

### `cylinder(radius: Float = 0.5, height: Float = 1, detail: Int = 24)`

Draws a cylinder with caps.

```swift
cylinder(radius: 30, height: 100)
```

## Cone

### `cone(radius: Float = 0.5, height: Float = 1, detail: Int = 24)`

Draws a cone with a flat base.

```swift
cone(radius: 40, height: 120)
```

## Torus

### `torus(ringRadius: Float = 0.5, tubeRadius: Float = 0.2, detail: Int = 24)`

Draws a torus (donut shape).

| Parameter | Description |
|-----------|-------------|
| `ringRadius` | Distance from center to tube center |
| `tubeRadius` | Radius of the tube |
| `detail` | Tessellation segments |

```swift
torus(ringRadius: 80, tubeRadius: 25)
```

## Plane

### `plane(_ width: Float, _ height: Float)`

Draws a flat rectangle in 3D space.

```swift
plane(200, 200)
```

## Custom Mesh

### `mesh(_ mesh: Mesh)`

Renders a pre-built `Mesh` object. Use `Mesh` static factory methods to create geometry:

```swift
let myMesh = Mesh.box(device: renderer.device, width: 1, height: 1, depth: 1)
mesh(myMesh)
```

### Mesh Factory Methods

| Method | Description |
|--------|-------------|
| `Mesh.box(device:width:height:depth:)` | Box mesh |
| `Mesh.sphere(device:radius:detail:)` | Sphere mesh |
| `Mesh.plane(device:width:height:)` | Plane mesh |
| `Mesh.cylinder(device:radius:height:detail:)` | Cylinder mesh |
| `Mesh.cone(device:radius:height:detail:)` | Cone mesh |
| `Mesh.torus(device:ringRadius:tubeRadius:detail:)` | Torus mesh |

## Example: 3D Scene

```swift
@main
final class Scene3D: Sketch {
    func draw() {
        background(0.1)

        camera(eye: SIMD3(0, 200, 500), center: SIMD3(0, 0, 0))
        perspective()
        lights()

        fill(Color.red)
        pushMatrix()
        translate(0, 0, 0)
        rotateY(time)
        box(100)
        popMatrix()

        fill(Color.blue)
        pushMatrix()
        translate(200, 0, 0)
        sphere(50)
        popMatrix()
    }
}
```

## See Also

- [Camera](camera.md) - Camera and projection
- [Lighting](lighting.md) - Light sources
- [Material & Texture](material.md) - Surface materials
- [Transform](transform.md) - 3D transforms
