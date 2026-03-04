import metaphor

@main
final class RadialGradient: Sketch {
    var dim: Float = 0
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Radial Gradient") }
    func setup() {
        dim = width / 2
        background(0)
        colorMode(.hsb, 360, 100, 100)
        noStroke()
        ellipseMode(.radius)
        frameRate(1)
    }
    func draw() {
        background(0)
        var x: Float = 0
        while x <= width {
            drawGradient(x, height / 2)
            x += dim
        }
    }
    private func drawGradient(_ x: Float, _ y: Float) {
        let radius = Int(dim / 2)
        var h = random(0, 360)
        var r = radius
        while r > 0 {
            fill(h, 90, 90)
            ellipse(x, y, Float(r), Float(r))
            h = Float(Int(h + 1) % 360)
            r -= 1
        }
    }
}
