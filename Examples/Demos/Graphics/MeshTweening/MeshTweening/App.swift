import metaphor

// NOTE: This example requires PShape retained-mode API with custom vertex attributes (attribPosition)
// which is not available in metaphor.
// Original Processing source: MeshTweening.pde

@main
final class MeshTweening: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "MeshTweening (Stub)", width: 640, height: 360)
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape retained-mode API\nwith custom vertex attributes (attribPosition)\nnot available in metaphor", width / 2, height / 2)
    }
}
