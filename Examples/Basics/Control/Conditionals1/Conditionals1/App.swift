import metaphor

@main
final class Conditionals1: Sketch {
    var config: SketchConfig { SketchConfig(title: "Conditionals 1", width: 640, height: 360) }
    func setup() { noLoop() }
    func draw() {
        background(0)
        var i: Float = 10
        while i < width {
            if Int(i) % 20 == 0 {
                stroke(255)
                line(i, 80, i, height / 2)
            } else {
                stroke(153)
                line(i, 20, i, 180)
            }
            i += 10
        }
    }
}
