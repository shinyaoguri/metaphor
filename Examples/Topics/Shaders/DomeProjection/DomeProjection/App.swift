import metaphor

// NOTE: This example requires cubemap rendering which is not available in metaphor.
// Original Processing source: DomeProjection.pde

@main
final class DomeProjection: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "DomeProjection (Stub)")
    }
    func setup() { noLoop() }
    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires cubemap rendering\nnot available in metaphor", width / 2, height / 2)
    }
}
