import metaphor

// NOTE: This example requires PShape retained-mode API (createShape(SPHERE), setTexture, shape)
// which is not available in metaphor.
// Original Processing source: Planets.pde

@main
final class Planets: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Planets (Stub)")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape retained-mode API\n(createShape(SPHERE), setTexture, shape)\nnot available in metaphor", width / 2, height / 2)
    }
}
