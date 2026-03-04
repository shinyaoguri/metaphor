import metaphor

@main
final class Redraw: Sketch {
    var y: Float = 0
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Redraw") }
    func setup() {
        stroke(255)
        noLoop()
        y = height * 0.5
    }
    func draw() {
        background(0)
        y -= 4
        if y < 0 { y = height }
        line(0, y, width, y)
    }
    func mousePressed() {
        redraw()
    }
}
