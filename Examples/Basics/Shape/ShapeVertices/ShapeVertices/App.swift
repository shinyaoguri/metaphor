import metaphor

// NOTE: This example requires PShape SVG loading with vertex iteration
// which is not available in metaphor.
// Original Processing source: ShapeVertices.pde

@main
final class ShapeVertices: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "ShapeVertices (Stub)", width: 640, height: 360)
    }

    func setup() { noLoop() }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape SVG (loadShape/getVertex)\nnot available in metaphor", width / 2, height / 2)
    }
}
