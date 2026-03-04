import metaphor

@main
final class IntegersFloats: Sketch {
    var a: Float = 0
    var b: Float = 0

    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Integers Floats") }

    func setup() {
        stroke(255)
    }

    func draw() {
        background(0)
        a += 1
        b += 0.2
        line(a, 0, a, height / 2)
        line(b, height / 2, b, height)
        if a > width { a = 0 }
        if b > width { b = 0 }
    }
}
