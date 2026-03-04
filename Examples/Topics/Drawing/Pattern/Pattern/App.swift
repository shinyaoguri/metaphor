import metaphor

@main
final class Pattern: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Pattern", width: 640, height: 360)
    }

    func setup() {
        background(102)
    }

    func draw() {
        variableEllipse(mouseX, mouseY, pmouseX, pmouseY)
    }

    func variableEllipse(_ x: Float, _ y: Float, _ px: Float, _ py: Float) {
        let speed = abs(x - px) + abs(y - py)
        stroke(speed)
        ellipse(x, y, speed, speed)
    }
}
