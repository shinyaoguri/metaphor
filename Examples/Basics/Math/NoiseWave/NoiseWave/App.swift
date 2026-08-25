import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Basics/Math/NoiseWave
// The original .pde is not bundled — see Examples/NOTICE.md.

@main
final class NoiseWave: Sketch {
    var yoff: Float = 0
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Noise Wave") }
    func draw() {
        background(51)
        fill(255)
        beginShape()
        var xoff: Float = 0
        var x: Float = 0
        while x <= width {
            let y = map(noise(xoff, yoff), 0, 1, 200, 300)
            vertex(x, y)
            xoff += 0.05
            x += 10
        }
        yoff += 0.01
        vertex(width, height)
        vertex(0, height)
        endShape(.close)
    }
}
