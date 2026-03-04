import metaphor

@main
final class OperatorPrecedence: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Operator Precedence") }
    func setup() { noLoop() }
    func draw() {
        background(51)
        noFill()
        stroke(204)
        for i in stride(from: 0, to: Int(width) - 20, by: 4) {
            if i > 30 + 70 { line(Float(i), 0, Float(i), 50) }
        }
        stroke(255)
        rect(Float(4 + 2 * 8), 52, 290, 48)
        rect(Float((4 + 2) * 8), 100, 290, 49)
        stroke(153)
        for i in stride(from: 0, to: Int(width), by: 2) {
            if (i > 20 && i < 50) || (i > 100 && i < Int(width) - 20) {
                line(Float(i), 151, Float(i), height - 1)
            }
        }
    }
}
