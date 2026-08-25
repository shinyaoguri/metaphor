import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Demos/Graphics/GetTessGroups
// The original .pde is not bundled — see Examples/NOTICE.md.

// NOTE: This example requires PShape tessellation API (getTessellation)
// which is not available in metaphor.

@main
final class GetTessGroups: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "GetTessGroups (Stub)")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape tessellation API\n(getTessellation)\nnot available in metaphor", width / 2, height / 2)
    }
}
