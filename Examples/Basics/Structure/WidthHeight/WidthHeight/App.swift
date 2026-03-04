import metaphor

@main
final class WidthHeight: Sketch {
    var config: SketchConfig { SketchConfig(title: "Width and Height", width: 640, height: 360) }
    func draw() {
        background(127)
        noStroke()
        var i: Float = 0
        while i < height {
            fill(129, 206, 15)
            rect(0, i, width, 10)
            fill(255)
            rect(i, 0, 10, height)
            i += 20
        }
    }
}
