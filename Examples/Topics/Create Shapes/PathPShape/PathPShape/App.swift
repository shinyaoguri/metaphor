import metaphor

/// PathPShape
///
/// A simple sine wave path using MShape with beginShape/vertex/endShape.
@main
final class PathPShape: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "PathPShape")
    }

    var path: MShape!

    func setup() {
        // Create the shape
        path = createShape()
        path.beginShape()
        // Set fill and stroke
        path.noFill()
        path.stroke(.white)
        path.strokeWeight(2)

        // Calculate the path as a sine wave
        var x: Float = 0
        var a: Float = 0
        while a < Float.pi * 2 {
            path.vertex(x, sin(a) * 100)
            x += 5
            a += 0.1
        }
        // The path is complete
        path.endShape()
    }

    func draw() {
        background(51)
        // Draw the path at the mouse location
        translate(mouseX, mouseY)
        shape(path)
    }
}
