import metaphor

// NOTE: This example requires PShape tessellation API (getTessellation)
// which is not available in metaphor.
// Original Processing source: GetTessGroups.pde

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
