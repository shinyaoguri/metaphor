import metaphor

// NOTE: This example requires PDB file parser (specialized molecular data format)
// which is not available in metaphor.
// Original Processing source: Ribbons.pde

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
