import metaphor

// NOTE: Original uses a GLSL edge filter applied via filter() on 3D scene.
// This version draws the 3D scene with wireframe to approximate edge effect.

@main
final class EdgeFilter: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "EdgeFilter", width: 640, height: 360)
    }

    var applyFilter = true

    func setup() {
        noStroke()
    }

    func draw() {
        background(0)
        lights()

        translate(width / 2, height / 2)

        pushMatrix()
        rotateX(Float(frameCount) * 0.01)
        rotateY(Float(frameCount) * 0.01)

        if applyFilter {
            // Wireframe to simulate edge detection
            stroke(255)
            noFill()
            box(120)
        } else {
            noStroke()
            fill(200)
            box(120)
        }
        popMatrix()

        rotateY(Float(frameCount) * 0.02)
        translate(150, 0)

        // Sphere is always solid (drawn after filter in original)
        noStroke()
        fill(200)
        sphere(40)
    }

    func mousePressed() {
        applyFilter = !applyFilter
    }
}
