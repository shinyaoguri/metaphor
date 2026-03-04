import metaphor

// NOTE: This example requires PShape retained-mode API (createShape, addChild)
// which is not available in metaphor.
// Original Processing source: DynamicParticlesRetained.pde

@main
final class DynamicParticlesRetained: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "DynamicParticlesRetained (Stub)")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape retained-mode API\n(createShape, addChild)\nnot available in metaphor", width / 2, height / 2)
    }
}
