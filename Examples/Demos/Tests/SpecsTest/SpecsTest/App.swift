import metaphor

// NOTE: This example requires OpenGL specification query API which is not available in metaphor.
// Original Processing source: SpecsTest.pde

@main
final class SpecsTest: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "SpecsTest (Stub)", width: 640, height: 360)
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires OpenGL specification query API\nnot available in metaphor", width / 2, height / 2)
    }
}
