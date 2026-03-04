import metaphor

@main
final class Mouse2D: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Mouse 2D") }
    func setup() {
        noStroke()
        rectMode(.center)
    }
    func draw() {
        background(51)
        fill(255, 204)
        rect(mouseX, height / 2, mouseY / 2 + 10, mouseY / 2 + 10)
        fill(255, 204)
        let inverseX = width - mouseX
        let inverseY = height - mouseY
        rect(inverseX, height / 2, inverseY / 2 + 10, inverseY / 2 + 10)
    }
}
