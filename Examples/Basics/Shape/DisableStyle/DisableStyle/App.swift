import metaphor

/// DisableStyle
///
/// Demonstrates disableStyle() and enableStyle() on an MShape.
/// Left: shape drawn with custom fill/stroke (shape's own style disabled).
/// Right: shape drawn with its original captured style.
@main
final class DisableStyle: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "DisableStyle")
    }

    var star: MShape!

    func setup() {
        // Create a star shape with its own style (red fill, no stroke)
        star = createShape()
        star.beginShape()
        star.fill(.red)
        star.noStroke()
        for i in 0..<10 {
            let angle = Float(i) * Float.pi / 5
            let r: Float = (i % 2 == 0) ? 80 : 30
            star.vertex(cos(angle) * r, sin(angle) * r)
        }
        star.endShape(.close)
    }

    func draw() {
        background(51)

        // Left side: disable the shape's style and use our own
        star.disableStyle()
        fill(0, 102, 153)
        stroke(255)
        strokeWeight(2)
        shape(star, width * 0.25, height / 2)

        // Right side: enable the shape's own style (red, no stroke)
        star.enableStyle()
        shape(star, width * 0.75, height / 2)
    }
}
