# Transform

Transform functions for positioning, rotating, and scaling shapes in 2D and 3D space.

## 2D Transform Stack

### `push()` / `pop()`

Save and restore the current 2D transform state. Always use in pairs.

```swift
push()
translate(100, 100)
rotate(time)
rect(-25, -25, 50, 50)  // Rotates around (100, 100)
pop()

// Transform is back to normal here
rect(0, 0, 50, 50)
```

### `translate(_ x: Float, _ y: Float)`

Moves the 2D origin by (x, y) pixels.

```swift
translate(width / 2, height / 2)
circle(0, 0, 100)  // Draws at center of screen
```

### `rotate(_ angle: Float)`

Rotates the 2D coordinate system. Angle is in **radians**.

```swift
push()
translate(width / 2, height / 2)
rotate(Float.pi / 4)  // 45 degrees
rect(-50, -50, 100, 100)
pop()
```

### `scale(_ sx: Float, _ sy: Float)`

Scales the 2D coordinate system independently on each axis.

```swift
push()
scale(2.0, 0.5)  // 2x wide, half tall
rect(100, 100, 50, 50)
pop()
```

### `scale(_ s: Float)`

Uniform 2D scale.

```swift
push()
translate(width / 2, height / 2)
scale(2.0)
circle(0, 0, 50)  // Appears as diameter 200
pop()
```

## 3D Transform Stack

### `pushMatrix()` / `popMatrix()`

Save and restore the current 3D transform state. Always use in pairs.

```swift
pushMatrix()
translate(100, 0, 0)
rotateY(time)
box(50)
popMatrix()
```

### `translate(_ x: Float, _ y: Float, _ z: Float)`

Moves the 3D origin.

```swift
translate(0, 100, -200)
sphere(50)
```

### `rotateX(_ angle: Float)` / `rotateY(_ angle: Float)` / `rotateZ(_ angle: Float)`

Rotates around the specified axis. Angles in **radians**.

```swift
pushMatrix()
rotateX(time * 0.5)
rotateY(time * 0.7)
box(100)
popMatrix()
```

### `scale(_ x: Float, _ y: Float, _ z: Float)`

Scales the 3D coordinate system.

```swift
pushMatrix()
scale(1.0, 2.0, 0.5)
box(100)  // Tall, thin box
popMatrix()
```

## Example: Solar System

```swift
func draw() {
    background(0.05)
    camera(eye: SIMD3(0, 300, 600), center: SIMD3(0, 0, 0))
    perspective()
    lights()

    // Sun
    fill(Color.yellow)
    sphere(50)

    // Earth orbit
    pushMatrix()
    rotateY(time * 0.5)
    translate(200, 0, 0)

    fill(Color.blue)
    sphere(20)

    // Moon orbit
    pushMatrix()
    rotateY(time * 2.0)
    translate(40, 0, 0)
    fill(Color(gray: 0.7))
    sphere(8)
    popMatrix()

    popMatrix()
}
```

## See Also

- [2D Shapes](shapes-2d.md)
- [3D Shapes](shapes-3d.md)
- [Camera](camera.md)
