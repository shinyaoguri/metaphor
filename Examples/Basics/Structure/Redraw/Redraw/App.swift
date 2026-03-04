import metaphor

@main
final class Redraw: Sketch {
    var y: Float = 0
    var config: SketchConfig { SketchConfig(title: "Redraw", width: 640, height: 360) }
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
