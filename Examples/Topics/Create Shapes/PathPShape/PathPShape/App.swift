import metaphor

// NOTE: This example requires PShape retained-mode API (createShape, vertex, shape)
// which is not available in metaphor.
// Original Processing source: PathPShape.pde

@main
final class PathPShape: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "PathPShape (Stub)", width: 640, height: 360)
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape retained-mode API\n(createShape, vertex, shape)\nnot available in metaphor", width / 2, height / 2)
    }
}
