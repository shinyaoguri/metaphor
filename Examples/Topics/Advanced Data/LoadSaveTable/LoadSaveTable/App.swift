import metaphor

// NOTE: This example requires loadTable/saveTable which is not available in metaphor.

@main
final class LoadSaveTable: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "LoadSaveTable (Stub)")
    }
    func setup() { noLoop() }
    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires loadTable/saveTable\nnot available in metaphor", width / 2, height / 2)
    }
}
