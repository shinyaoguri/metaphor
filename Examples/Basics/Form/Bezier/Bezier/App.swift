import metaphor

@main
final class Bezier: Sketch {
    var config: SketchConfig { SketchConfig(title: "Bezier", width: 640, height: 360) }
    func setup() {
        stroke(255)
        noFill()
    }
    func draw() {
        background(0)
        for i in stride(from: 0, to: 200, by: 20) {
            bezier(mouseX - Float(i) / 2.0, 40 + Float(i), 410, 20, 440, 300, 240 - Float(i) / 16.0, 300 + Float(i) / 8.0)
        }
    }
}
