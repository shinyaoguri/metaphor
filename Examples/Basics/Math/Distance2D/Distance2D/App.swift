import metaphor

@main
final class Distance2D: Sketch {
    var maxDist: Float = 0
    var config: SketchConfig { SketchConfig(title: "Distance 2D", width: 640, height: 360) }
    func setup() {
        noStroke()
        maxDist = dist(0, 0, width, height)
    }
    func draw() {
        background(0)
        var i: Float = 0
        while i <= width {
            var j: Float = 0
            while j <= height {
                let size = dist(mouseX, mouseY, i, j) / maxDist * 66
                ellipse(i, j, size, size)
                j += 20
            }
            i += 20
        }
    }
}
