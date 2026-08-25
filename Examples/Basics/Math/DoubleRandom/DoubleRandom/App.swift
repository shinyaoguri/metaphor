import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Basics/Math/DoubleRandom
// The original .pde is not bundled — see Examples/NOTICE.md.

@main
final class DoubleRandom: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Double Random") }
    func setup() { stroke(255); frameRate(1) }
    func draw() {
        background(0)
        var rand: Float = 0
        let steps = 301
        for i in 1..<steps {
            point(width / Float(steps) * Float(i), height / 2 + random(-rand, rand))
            rand += random(-5, 5)
        }
    }
}
