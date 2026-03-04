import metaphor

@main
final class Noise2D: Sketch {
    let increment: Float = 0.02
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Noise 2D") }
    func draw() {
        let detail = map(mouseX, 0, width, 0.1, 0.6)
        noiseDetail(octaves: 8, falloff: detail)
        var xoff: Float = 0
        for x in 0..<Int(width) {
            xoff += increment
            var yoff: Float = 0
            for y in 0..<Int(height) {
                yoff += increment
                let bright = noise(xoff, yoff) * 255
                stroke(bright)
                point(Float(x), Float(y))
            }
        }
    }
}
