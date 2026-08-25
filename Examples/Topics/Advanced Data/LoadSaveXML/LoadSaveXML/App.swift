import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Topics/Advanced%20Data/LoadSaveXML
// The original .pde is not bundled — see Examples/NOTICE.md.

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
