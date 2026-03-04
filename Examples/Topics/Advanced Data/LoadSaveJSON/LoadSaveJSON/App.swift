import metaphor

// NOTE: This example requires loadJSON/saveJSON which is not available in metaphor.

@main
final class LoadSaveJSON: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "LoadSaveJSON (Stub)")
    }
    func setup() { noLoop() }
    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires loadJSON/saveJSON\nnot available in metaphor", width / 2, height / 2)
    }
}
