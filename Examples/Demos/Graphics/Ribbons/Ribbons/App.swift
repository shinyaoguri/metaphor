import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Demos/Graphics/Ribbons
// The original .pde is not bundled — see Examples/NOTICE.md.

// NOTE: This example requires PDB file parser (specialized molecular data format)
// which is not available in metaphor.

@main
final class Ribbons: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Ribbons (Stub)")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PDB file parser\n(specialized molecular data format)\nnot available in metaphor", width / 2, height / 2)
    }
}
