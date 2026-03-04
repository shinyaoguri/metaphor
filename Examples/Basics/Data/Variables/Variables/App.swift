import metaphor

@main
final class Variables: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Variables") }
    func setup() { noLoop() }
    func draw() {
        background(0)
        stroke(153)
        strokeWeight(4)
        strokeCap(.square)

        var a: Float = 50
        var b: Float = 120
        let c: Float = 180

        line(a, b, a + c, b)
        line(a, b + 10, a + c, b + 10)
        line(a, b + 20, a + c, b + 20)
        line(a, b + 30, a + c, b + 30)

        a = a + c
        b = height - b

        line(a, b, a + c, b)
        line(a, b + 10, a + c, b + 10)
        line(a, b + 20, a + c, b + 20)
        line(a, b + 30, a + c, b + 30)

        a = a + c
        b = height - b

        line(a, b, a + c, b)
        line(a, b + 10, a + c, b + 10)
        line(a, b + 20, a + c, b + 20)
        line(a, b + 30, a + c, b + 30)
    }
}
