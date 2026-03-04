import metaphor

@main
final class NoBackgroundTest: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 400, height: 400, title: "NoBackgroundTest")
    }

    func setup() {
        background(255, 0, 0)
        fill(255, 150)
    }

    func draw() {
        // No background() call — previous frames persist (trail effect)
        ellipse(mouseX, mouseY, 100, 100)
    }
}
