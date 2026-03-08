import metaphor

@main
final class Noise3D: Sketch {
    let increment: Float = 0.01
    var zoff: Float = 0
    let zincrement: Float = 0.02
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Noise 3D") }
    func setup() { frameRate(30) }
    func draw() {
        loadPixels()
        let w = Int(width)
        let h = Int(height)
        var xoff: Float = 0
        for x in 0..<w {
            xoff += increment
            var yoff: Float = 0
            for y in 0..<h {
                yoff += increment
                let bright = noise(xoff, yoff, zoff) * 255
                pixels[y * w + x] = color(bright, bright, bright)
            }
        }
        updatePixels()
        zoff += zincrement
    }
}
