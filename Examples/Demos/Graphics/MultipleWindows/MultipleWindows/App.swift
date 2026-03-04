import metaphor

// NOTE: This example requires multiple window support
// which is not available in metaphor (single window per Sketch instance).
// Original Processing source: MultipleWindows.pde

@main
final class MultipleWindows: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "MultipleWindows (Stub)")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires multiple window support\nnot available in metaphor\n(single window per Sketch instance)", width / 2, height / 2)
    }
}
