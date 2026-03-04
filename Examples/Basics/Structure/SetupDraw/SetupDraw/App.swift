import metaphor

@main
final class SetupDraw: Sketch {
    var y: Float = 180
    var config: SketchConfig { SketchConfig(title: "Setup and Draw", width: 640, height: 360) }
    func setup() {
        stroke(255)
    }
    func draw() {
        background(0)
        line(0, y, width, y)
        y -= 1
        if y < 0 { y = height }
    }
}
