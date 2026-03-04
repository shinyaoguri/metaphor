import metaphor

@main
final class SineWave: Sketch {
    let xspacing: Float = 16
    var w: Float = 0; var theta: Float = 0
    let amplitude: Float = 75; let period: Float = 500
    var dx: Float = 0; var yvalues: [Float] = []
    var config: SketchConfig { SketchConfig(title: "Sine Wave", width: 640, height: 360) }
    func setup() {
        w = width + 16
        dx = (Float.pi * 2 / period) * xspacing
        yvalues = [Float](repeating: 0, count: Int(w / xspacing))
    }
    func draw() {
        background(0)
        theta += 0.02
        var x = theta
        for i in 0..<yvalues.count { yvalues[i] = sin(x) * amplitude; x += dx }
        noStroke(); fill(255)
        for x in 0..<yvalues.count {
            ellipse(Float(x) * xspacing, height / 2 + yvalues[x], 16, 16)
        }
    }
}
