import metaphor

@main
final class AdditiveWave: Sketch {
    let xspacing: Float = 8
    let maxwaves = 4
    var theta: Float = 0
    var amplitude: [Float] = []
    var dx: [Float] = []
    var yvalues: [Float] = []
    var w: Float = 0
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Additive Wave") }
    func setup() {
        frameRate(30)
        w = width + 16
        for _ in 0..<maxwaves {
            amplitude.append(random(10, 30))
            let period = random(100, 300)
            dx.append((Float.pi * 2 / period) * xspacing)
        }
        yvalues = [Float](repeating: 0, count: Int(w / xspacing))
    }
    func draw() {
        background(0)
        theta += 0.02
        for i in 0..<yvalues.count { yvalues[i] = 0 }
        for j in 0..<maxwaves {
            var x = theta
            for i in 0..<yvalues.count {
                if j % 2 == 0 { yvalues[i] += sin(x) * amplitude[j] }
                else { yvalues[i] += cos(x) * amplitude[j] }
                x += dx[j]
            }
        }
        noStroke()
        fill(255, 50)
        ellipseMode(.center)
        for x in 0..<yvalues.count {
            ellipse(Float(x) * xspacing, height / 2 + yvalues[x], 16, 16)
        }
    }
}
