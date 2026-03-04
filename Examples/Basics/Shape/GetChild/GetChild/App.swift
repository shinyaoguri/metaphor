import metaphor

// NOTE: This example requires PShape SVG loading with getChild()
// which is not available in metaphor.
// Original Processing source: GetChild.pde

@main
final class GetChild: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "GetChild (Stub)")
    }

    func setup() { noLoop() }

    func draw() {
        background(51)
        fill(.white)
        textAlign(.center, .center)
        textSize(14)
        text("This example requires PShape SVG (loadShape/getChild)\nnot available in metaphor", width / 2, height / 2)
    }
}
