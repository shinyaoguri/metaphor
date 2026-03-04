import metaphor

// NOTE: This example requires PShape retained-mode API (createShape, addChild)
// which is not available in metaphor.
// Original Processing source: ParticleSystemPShape.pde

@main
final class ParticleSystemPShape: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "ParticleSystemPShape (Stub)", width: 640, height: 360)
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
