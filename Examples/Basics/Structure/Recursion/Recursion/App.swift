import metaphor

@main
final class Recursion: Sketch {
    var config: SketchConfig { SketchConfig(title: "Recursion", width: 640, height: 360) }
    func setup() {
        noStroke()
        noLoop()
    }
    func draw() {
        drawCircle(width / 2, 280, 6)
    }
    private func drawCircle(_ x: Float, _ radius: Float, _ level: Int) {
        let tt = 126.0 * Float(level) / 4.0
        fill(tt)
        ellipse(x, height / 2, radius * 2, radius * 2)
        if level > 1 {
            drawCircle(x - radius / 2, radius / 2, level - 1)
            drawCircle(x + radius / 2, radius / 2, level - 1)
        }
    }
}
