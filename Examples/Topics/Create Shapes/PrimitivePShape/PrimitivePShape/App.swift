import metaphor

// NOTE: This example requires PShape retained-mode API (createShape(RECT), shape)
// which is not available in metaphor.
// Original Processing source: PrimitivePShape.pde

@main
final class PrimitivePShape: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "PrimitivePShape (Stub)", width: 640, height: 360)
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape retained-mode API\n(createShape(RECT), shape)\nnot available in metaphor", width / 2, height / 2)
    }
}
