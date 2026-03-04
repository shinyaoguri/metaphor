import metaphor

@main
final class TriangleStrip: Sketch {
    let outsideRadius: Float = 150
    let insideRadius: Float = 100
    var config: SketchConfig { SketchConfig(title: "Triangle Strip", width: 640, height: 360) }
    func draw() {
        background(204)
        let x = width / 2
        let y = height / 2
        let numPoints = Int(map(mouseX, 0, width, 6, 60))
        var angle: Float = 0
        let angleStep: Float = 180.0 / Float(numPoints)

        beginShape(.triangleStrip)
        for _ in 0...numPoints {
            var px = x + cos(radians(angle)) * outsideRadius
            var py = y + sin(radians(angle)) * outsideRadius
            angle += angleStep
            vertex(px, py)
            px = x + cos(radians(angle)) * insideRadius
            py = y + sin(radians(angle)) * insideRadius
            vertex(px, py)
            angle += angleStep
        }
        endShape()
    }
}
