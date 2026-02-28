# Custom Shapes

Use `beginShape()` / `endShape()` to create complex geometry from individual vertices.

## Basic Usage

```swift
beginShape()
vertex(100, 100)
vertex(200, 50)
vertex(300, 100)
vertex(250, 200)
vertex(150, 200)
endShape(.close)
```

## Shape Modes

Pass a `ShapeMode` to `beginShape()` to control how vertices are interpreted:

### `.polygon` (default)

Vertices form a filled polygon.

```swift
fill(Color.cyan)
beginShape(.polygon)
vertex(100, 100)
vertex(200, 50)
vertex(300, 100)
vertex(250, 200)
vertex(150, 200)
endShape(.close)
```

### `.points`

Each vertex is drawn as a point (uses stroke color and weight).

```swift
stroke(Color.white)
strokeWeight(4)
beginShape(.points)
for i in 0..<100 {
    vertex(Float.random(in: 0...width), Float.random(in: 0...height))
}
endShape()
```

### `.lines`

Vertices are paired into lines (1-2, 3-4, 5-6, ...).

```swift
stroke(Color.yellow)
strokeWeight(2)
beginShape(.lines)
vertex(100, 100)
vertex(200, 200)
vertex(300, 100)
vertex(400, 200)
endShape()
```

### `.triangles`

Every 3 vertices form a triangle.

```swift
fill(Color.red)
beginShape(.triangles)
vertex(100, 200)
vertex(150, 100)
vertex(200, 200)
vertex(250, 200)
vertex(300, 100)
vertex(350, 200)
endShape()
```

### `.triangleStrip`

Connected strip of triangles. Each new vertex forms a triangle with the previous two.

```swift
fill(Color.green)
beginShape(.triangleStrip)
for i in 0..<20 {
    let x = Float(i) * 30 + 100
    let y: Float = (i % 2 == 0) ? 100 : 200
    vertex(x, y)
}
endShape()
```

### `.triangleFan`

Triangles fan out from the first vertex.

```swift
fill(Color.blue)
beginShape(.triangleFan)
vertex(width / 2, height / 2)  // Center
for i in 0...12 {
    let angle = Float(i) / 12.0 * Float.pi * 2
    vertex(width / 2 + cos(angle) * 100, height / 2 + sin(angle) * 100)
}
endShape()
```

## Close Mode

`endShape()` accepts a `CloseMode`:

| Mode | Description |
|------|-------------|
| `.open` | Leave shape open (default) |
| `.close` | Connect last vertex to first |

## Example: Animated Star

```swift
func draw() {
    background(0.1)
    push()
    translate(width / 2, height / 2)
    rotate(time * 0.5)

    fill(Color.yellow)
    noStroke()
    beginShape()
    let points = 5
    for i in 0..<points * 2 {
        let angle = Float(i) * Float.pi / Float(points) - Float.pi / 2
        let r: Float = (i % 2 == 0) ? 100 : 45
        vertex(cos(angle) * r, sin(angle) * r)
    }
    endShape(.close)

    pop()
}
```

## See Also

- [2D Shapes](../api/shapes-2d.md) - Built-in shape primitives
- [Color & Style](../api/color.md) - Fill and stroke
- [Transform](../api/transform.md) - Positioning shapes
