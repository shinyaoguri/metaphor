import metaphor

@main
final class LoadDisplayOBJ: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Load Display OBJ", width: 640, height: 360)
    }

    var ry: Float = 0

    func setup() {
        // NOTE: The original Processing example loads rocket.obj via loadShape().
        // In metaphor, use ModelIOLoader.load(path:) to load OBJ files:
        //   let mesh = try ModelIOLoader.load(path: "/path/to/rocket.obj")
        // This example uses a simple box as a placeholder.
    }

    func draw() {
        background(0)
        lights()
        translate3D(width / 2, height / 2 + 100, -200)
        rotateZ(Float.pi)
        rotateY(ry)
        fill(200, 200, 220)
        box(0, 0, 0, 60, 160, 60)
        ry += 0.02
    }
}
