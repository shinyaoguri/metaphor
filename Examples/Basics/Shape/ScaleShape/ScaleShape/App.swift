import metaphor

// NOTE: This example requires PShape SVG loading with shape scaling
// which is not available in metaphor.
// Original Processing source: ScaleShape.pde

@main
final class ScaleShape: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ScaleShape (Stub)")
    }

    func setup() { noLoop() }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape SVG (loadShape/scale)\nnot available in metaphor", width / 2, height / 2)
    }
}
