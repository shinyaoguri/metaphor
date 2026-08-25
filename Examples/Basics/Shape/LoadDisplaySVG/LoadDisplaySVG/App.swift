import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Basics/Shape/LoadDisplaySVG
// The original .pde is not bundled — see Examples/NOTICE.md.

// NOTE: This example requires SVG file loading via loadShape()
// which is not available in metaphor.

@main
final class LoadDisplaySVG: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "LoadDisplaySVG (Stub)")
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
