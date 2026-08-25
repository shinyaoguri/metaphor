import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Demos/Graphics/TessUpdate
// The original .pde is not bundled — see Examples/NOTICE.md.

// NOTE: This example requires PShape tessellation API (setVertex on tessellated shapes)
// which is not available in metaphor.

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
