import metaphor

@main
final class IncrementDecrement: Sketch {
    var a: Float = 0; var b: Float = 0; var direction = true
    var config: SketchConfig { SketchConfig(title: "Increment Decrement", width: 640, height: 360) }
    func setup() { colorMode(.rgb, width); b = width; frameRate(30) }
    func draw() {
        a += 1
        if a > width { a = 0; direction = !direction }
        stroke(direction ? a : width - a)
        line(a, 0, a, height / 2)
        b -= 1
        if b < 0 { b = width }
        stroke(direction ? width - b : b)
        line(b, height / 2 + 1, b, height)
    }
}
