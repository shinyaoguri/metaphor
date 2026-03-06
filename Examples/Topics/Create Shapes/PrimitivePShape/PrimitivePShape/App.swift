import metaphor

/// PrimitivePShape
///
/// Using MShape to display a primitive shape (ellipse).
/// The shape's style can be dynamically changed each frame.
@main
final class PrimitivePShape: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "PrimitivePShape")
    }

    var circle: MShape!

    func setup() {
        // Creating the MShape as an ellipse
        circle = createShape(.ellipse(x: 0, y: 0, width: 100, height: 50))
    }

    func draw() {
        background(51)

        // Dynamically set the stroke and fill of the shape
        circle.setStroke(.white)
        circle.setStrokeWeight(4)
        let grayValue = map(mouseX, 0, width, 0, 255)
        circle.setFill(Color(gray: grayValue / 255.0))

        // Use translate to move the shape to mouse position
        translate(mouseX, mouseY)
        // Drawing the MShape
        shape(circle)
    }
}
