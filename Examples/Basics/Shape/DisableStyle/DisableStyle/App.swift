import metaphor

// NOTE: This example requires PShape SVG loading with disableStyle/enableStyle
// which is not available in metaphor.
// Original Processing source: DisableStyle.pde

@main
final class DisableStyle: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "DisableStyle (Stub)")
    }

    func setup() { noLoop() }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape SVG (loadShape/disableStyle)\nnot available in metaphor", width / 2, height / 2)
    }
}
