import metaphor

@main
final class ContinuousLines: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Continuous Lines", width: 640, height: 360)
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
