import metaphor

// NOTE: This example requires raw OpenGL access (beginPGL, endPGL)
// which is not available in metaphor (Metal-only library).
// Original Processing source: LowLevelGLVboSeparate.pde

@main
final class LowLevelGLVboSeparate: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "LowLevelGLVboSeparate (Stub)")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires raw OpenGL access\n(beginPGL, endPGL)\nnot available in metaphor (Metal-only)", width / 2, height / 2)
    }
}
