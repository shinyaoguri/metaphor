import metaphor

@main
final class ContinuousLines: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Continuous Lines")
    }

    func setup() {
        background(102)
    }

    func draw() {
        stroke(255)
        if isMousePressed {
            line(mouseX, mouseY, pmouseX, pmouseY)
        }
    }
}
