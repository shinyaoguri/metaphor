import metaphor

@main
final class WaveGradient: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Wave Gradient") }
    func setup() {
        noLoop()
    }
    func draw() {
        background(200)
        let amplitude: Float = 30
        var frequency: Float = 0
        // Use step > 1 with matching strokeWeight to fill gaps.
        // Processing's set() manipulates pixels directly; metaphor draws geometry,
        // so per-pixel rendering is too heavy. Step 2 gives a good visual balance.
        let step = 2
        strokeWeight(Float(step))

        for i in stride(from: -75, to: Int(height) + 75, by: step) {
            var angle: Float = 0
            frequency += 0.002 * Float(step)
            for j in stride(from: 0, to: Int(width) + 75, by: step) {
                let py = Float(i) + sin(radians(angle)) * amplitude
                angle += frequency * Float(step)
                let r = abs(py - Float(i)) * 255.0 / amplitude
                let g = 255.0 - abs(py - Float(i)) * 255.0 / amplitude
                let b = Float(j) * (255.0 / (width + 50))
                stroke(r, g, b)
                point(Float(j), py)
            }
        }
    }
}
