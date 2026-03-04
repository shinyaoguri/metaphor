import metaphor

@main
final class Functions: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Functions") }
    func setup() {
        background(51)
        noStroke()
        noLoop()
    }
    func draw() {
        drawTarget(width * 0.25, height * 0.4, 200, 4)
        drawTarget(width * 0.5, height * 0.5, 300, 10)
        drawTarget(width * 0.75, height * 0.3, 120, 6)
    }
    private func drawTarget(_ xloc: Float, _ yloc: Float, _ size: Int, _ num: Int) {
        let grayvalues = 255.0 / Float(num)
        let steps = Float(size) / Float(num)
        for i in 0..<num {
            fill(Float(i) * grayvalues)
            ellipse(xloc, yloc, Float(size) - Float(i) * steps, Float(size) - Float(i) * steps)
        }
    }
}
