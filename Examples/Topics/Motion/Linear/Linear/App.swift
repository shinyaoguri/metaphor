import metaphor

@main
final class Linear: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Linear", width: 640, height: 360)
    }

    var a: Float = 0

    func setup() {
        stroke(255)
        a = height / 2
    }

    func draw() {
        background(51)
        line(0, a, width, a)
        a -= 0.5
        if a < 0 { a = height }
    }
}
