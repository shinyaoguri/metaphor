import metaphor

// NOTE: This example requires PShape retained-mode API (createShape, shape)
// which is not available in metaphor.
// Original Processing source: PolygonPShapeOOP.pde

@main
final class PolygonPShapeOOP: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "PolygonPShapeOOP (Stub)", width: 640, height: 360)
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape retained-mode API\n(createShape, shape)\nnot available in metaphor", width / 2, height / 2)
    }
}
