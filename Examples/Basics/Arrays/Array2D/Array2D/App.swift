import metaphor

@main
final class Array2D: Sketch {
    var distances: [[Float]] = []
    let spacer = 10
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Array 2D") }
    func setup() {
        let maxDist = dist(width / 2, height / 2, width, height)
        distances = (0..<Int(width)).map { x in
            (0..<Int(height)).map { y in
                dist(width / 2, height / 2, Float(x), Float(y)) / maxDist * 255
            }
        }
        strokeWeight(6)
        noLoop()
    }
    func draw() {
        background(0)
        for y in stride(from: 0, to: Int(height), by: spacer) {
            for x in stride(from: 0, to: Int(width), by: spacer) {
                stroke(distances[x][y])
                point(Float(x + spacer / 2), Float(y + spacer / 2))
            }
        }
    }
}
