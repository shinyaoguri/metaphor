import metaphor

/// ScaleShape
///
/// Demonstrates per-shape scaling on an MShape.
/// The shape's scale is controlled by the mouse X position.
@main
final class ScaleShape: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ScaleShape")
    }

    var star: MShape!

    func setup() {
        // Create a star shape
        star = createShape()
        star.beginShape()
        star.fill(.yellow)
        star.stroke(.white)
        star.strokeWeight(2)
        for i in 0..<10 {
            let angle = Float(i) * Float.pi / 5
            let r: Float = (i % 2 == 0) ? 50 : 20
            star.vertex(cos(angle) * r, sin(angle) * r)
        }
        star.endShape(.close)
    }

    func draw() {
        background(51)

        // Map mouse X to zoom level (0.5 to 4.0)
        let zoom = map(mouseX, 0, width, 0.5, 4.0)

        // Reset and apply new scale each frame
        star.resetMatrix()
        star.scale(zoom)

        // Draw the shape centered
        translate(width / 2, height / 2)
        shape(star)
    }
}
