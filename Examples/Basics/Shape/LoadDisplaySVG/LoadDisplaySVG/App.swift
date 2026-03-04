import metaphor

// NOTE: This example requires SVG file loading via loadShape()
// which is not available in metaphor.
// Original Processing source: LoadDisplaySVG.pde

@main
final class LoadDisplaySVG: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "LoadDisplaySVG (Stub)", width: 640, height: 360)
    }

    func setup() { noLoop() }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires SVG loading (loadShape)\nnot available in metaphor", width / 2, height / 2)
    }
}
