import metaphor

@main
final class BeginEndContour: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "BeginEndContour", width: 640, height: 360)
    }

    var angle: Float = 0

    func setup() {}

    func draw() {
        background(52)

        pushMatrix()
        translate(width / 2, height / 2)
        rotate(angle)

        fill(0)
        stroke(255)
        strokeWeight(2)

        beginShape()
        // Exterior part of shape
        vertex(-100, -100)
        vertex(100, -100)
        vertex(100, 100)
        vertex(-100, 100)

        // Interior part of shape (hole)
        beginContour()
        vertex(-10, -10)
        vertex(-10, 10)
        vertex(10, 10)
        vertex(10, -10)
        endContour()

        endShape(.close)
        popMatrix()

        angle += 0.01
    }
}
