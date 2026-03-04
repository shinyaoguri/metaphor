import metaphor

@main
final class NoBackgroundTest: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "NoBackgroundTest", width: 400, height: 400)
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
