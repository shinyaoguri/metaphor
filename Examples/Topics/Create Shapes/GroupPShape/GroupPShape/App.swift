import metaphor

// NOTE: This example requires PShape retained-mode API (createShape, shape, getChild)
// which is not available in metaphor.
// Original Processing source: GroupPShape.pde

@main
final class GroupPShape: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "GroupPShape (Stub)")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape retained-mode API\n(createShape, shape, getChild)\nnot available in metaphor", width / 2, height / 2)
    }
}
