import metaphor

/// PolygonPShape
///
/// Using MShape to display a custom polygon (star).
@main
final class PolygonPShape: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "PolygonPShape")
    }

    var star: MShape!

    func setup() {
        // First create the shape
        star = createShape()
        star.beginShape()
        // You can set fill and stroke
        star.fill(102)
        star.stroke(.white)
        star.strokeWeight(2)
        // Here, we are hardcoding a series of vertices
        star.vertex(0, -50)
        star.vertex(14, -20)
        star.vertex(47, -15)
        star.vertex(23, 7)
        star.vertex(29, 40)
        star.vertex(0, 25)
        star.vertex(-29, 40)
        star.vertex(-23, 7)
        star.vertex(-47, -15)
        star.vertex(-14, -20)
        star.endShape(.close)
    }

    func draw() {
        background(51)
        // We can use translate to move the MShape
        translate(mouseX, mouseY)
        // Display the shape
        shape(star)
    }
}
