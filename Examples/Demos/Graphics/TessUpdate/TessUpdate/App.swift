import metaphor

// NOTE: This example requires PShape tessellation API (setVertex on tessellated shapes)
// which is not available in metaphor.
// Original Processing source: TessUpdate.pde

@main
final class TessUpdate: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "TessUpdate (Stub)")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape tessellation API\n(setVertex on tessellated shapes)\nnot available in metaphor", width / 2, height / 2)
    }
}
