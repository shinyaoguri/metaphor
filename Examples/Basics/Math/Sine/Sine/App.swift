import metaphor

@main
final class Sine: Sketch {
    var diameter: Float = 0; var angle: Float = 0
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Sine") }
    func setup() { diameter = height - 10; noStroke(); fill(255, 204, 0) }
    func draw() {
        background(0)
        let d1 = 10 + (sin(angle) * diameter / 2) + diameter / 2
        let d2 = 10 + (sin(angle + Float.pi / 2) * diameter / 2) + diameter / 2
        let d3 = 10 + (sin(angle + Float.pi) * diameter / 2) + diameter / 2
        ellipse(0, height / 2, d1, d1)
        ellipse(width / 2, height / 2, d2, d2)
        ellipse(width, height / 2, d3, d3)
        angle += 0.02
    }
}
