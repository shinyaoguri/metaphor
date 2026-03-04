import metaphor

@main
final class ResizeTest: Sketch {
    var config: SketchConfig {
        // Note: windowResizable not directly available in metaphor
        SketchConfig(width: 400, height: 400, title: "ResizeTest")
    }

    func setup() {}

    func draw() {
        background(255, 0, 0)
        ellipse(width / 2, height / 2, 100, 50)
    }
}
