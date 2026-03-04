import metaphor

@main
final class Conditionals2: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Conditionals 2") }
    func setup() { noLoop() }
    func draw() {
        background(0)
        var i: Float = 2
        while i < width - 2 {
            if Int(i) % 20 == 0 {
                stroke(255)
                line(i, 80, i, height / 2)
            } else if Int(i) % 10 == 0 {
                stroke(153)
                line(i, 20, i, 180)
            } else {
                stroke(102)
                line(i, height / 2, i, height - 20)
            }
            i += 2
        }
    }
}
