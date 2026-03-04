import metaphor

// NOTE: This example requires loadXML/saveXML which is not available in metaphor.

@main
final class LoadSaveXML: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "LoadSaveXML (Stub)")
    }
    func setup() { noLoop() }
    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires loadXML/saveXML\nnot available in metaphor", width / 2, height / 2)
    }
}
