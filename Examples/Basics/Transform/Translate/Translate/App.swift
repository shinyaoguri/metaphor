import metaphor

@main
final class Translate: Sketch {
    var x: Float = 0
    let dim: Float = 80
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Translate") }
    func setup() { noStroke() }
    func draw() {
        background(102)
        x += 0.8
        if x > width + dim { x = -dim }
        translate(x, height / 2 - dim / 2)
        fill(255)
        rect(-dim / 2, -dim / 2, dim, dim)
        translate(x, dim)
        fill(0)
        rect(-dim / 2, -dim / 2, dim, dim)
    }
}
