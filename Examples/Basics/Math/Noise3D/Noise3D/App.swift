import metaphor

@main
final class Noise3D: Sketch {
    let increment: Float = 0.01
    var zoff: Float = 0
    let zincrement: Float = 0.02
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Noise 3D") }
    func setup() { frameRate(30) }
    func draw() {
        var xoff: Float = 0
        for x in 0..<Int(width) {
            xoff += increment
            var yoff: Float = 0
            for y in 0..<Int(height) {
                yoff += increment
                let bright = noise(xoff, yoff, zoff) * 255
                stroke(bright)
                point(Float(x), Float(y))
            }
        }
        zoff += zincrement
    }
}
