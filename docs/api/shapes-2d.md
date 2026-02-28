# 2D Shapes

Functions for drawing 2D shapes. All coordinates are in pixels, with (0, 0) at the top-left corner.

## Rectangles

### `rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float)`

Draws a rectangle.

| Parameter | Description |
|-----------|-------------|
| `x` | X position of the top-left corner |
| `y` | Y position of the top-left corner |
| `w` | Width |
| `h` | Height |

```swift
fill(Color.white)
rect(100, 100, 200, 150)
```

## Circles & Ellipses

### `circle(_ x: Float, _ y: Float, _ diameter: Float)`

Draws a circle centered at (x, y).

| Parameter | Description |
|-----------|-------------|
| `x` | Center X |
| `y` | Center Y |
| `diameter` | Diameter of the circle |

```swift
fill(Color.red)
circle(width / 2, height / 2, 100)
```

### `ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float)`

Draws an ellipse centered at (x, y).

| Parameter | Description |
|-----------|-------------|
| `x` | Center X |
| `y` | Center Y |
| `w` | Width |
| `h` | Height |

```swift
fill(Color.blue)
ellipse(400, 300, 200, 100)
```

## Lines

### `line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float)`

Draws a line between two points. Uses the current stroke color and weight.

```swift
stroke(Color.white)
strokeWeight(2)
line(0, 0, width, height)
```

### `point(_ x: Float, _ y: Float)`

Draws a single point. Uses the current stroke color and weight.

```swift
stroke(Color.yellow)
strokeWeight(4)
point(100, 100)
```

## Triangles

### `triangle(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float)`

Draws a triangle from three vertices.

```swift
fill(Color.green)
triangle(200, 100, 100, 300, 300, 300)
```

## Polygons

### `polygon(_ points: [(Float, Float)])`

Draws a filled polygon from an array of vertex positions.

```swift
fill(Color.cyan)
polygon([
    (100, 100),
    (200, 50),
    (300, 100),
    (250, 200),
    (150, 200)
])
```

## Arcs

### `arc(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ startAngle: Float, _ stopAngle: Float)`

Draws an arc (partial ellipse). Angles are in radians.

| Parameter | Description |
|-----------|-------------|
| `x` | Center X |
| `y` | Center Y |
| `w` | Width |
| `h` | Height |
| `startAngle` | Start angle in radians |
| `stopAngle` | End angle in radians |

```swift
fill(Color.orange)
arc(width / 2, height / 2, 200, 200, 0, Float.pi)
```

## Bezier Curves

### `bezier(_ x1: Float, _ y1: Float, _ cx1: Float, _ cy1: Float, _ cx2: Float, _ cy2: Float, _ x2: Float, _ y2: Float)`

Draws a cubic bezier curve with two control points.

| Parameter | Description |
|-----------|-------------|
| `x1, y1` | Start point |
| `cx1, cy1` | First control point |
| `cx2, cy2` | Second control point |
| `x2, y2` | End point |

```swift
noFill()
stroke(Color.white)
strokeWeight(2)
bezier(100, 400, 150, 100, 450, 100, 500, 400)
```

## See Also

- [Custom Shapes](../guides/custom-shapes.md) - beginShape / endShape for complex geometry
- [Color & Style](color.md) - fill, stroke, and blend modes
- [Transform](transform.md) - translate, rotate, scale
