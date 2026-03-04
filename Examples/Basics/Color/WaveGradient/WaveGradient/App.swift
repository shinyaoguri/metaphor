import metaphor

@main
final class WaveGradient: Sketch {
    var config: SketchConfig { SketchConfig(title: "Wave Gradient", width: 640, height: 360) }
    func setup() {
        noLoop()
    }
    func draw() {
        background(200)
        let amplitude: Float = 30
        let fillGap: Float = 2.5
        var frequency: Float = 0

        for i in stride(from: -75, to: Int(height) + 75, by: 1) {
            var angle: Float = 0
            frequency += 0.002
            for j in stride(from: 0, to: Int(width) + 75, by: 1) {
                let py = Float(i) + sin(radians(angle)) * amplitude
                angle += frequency
                let r = abs(py - Float(i)) * 255.0 / amplitude
                let g = 255.0 - abs(py - Float(i)) * 255.0 / amplitude
                let b = Float(j) * (255.0 / (width + 50))
                stroke(r, g, b)
                // Draw a small point to approximate pixel-level set()
                for filler in 0..<Int(fillGap) {
                    point(Float(j - filler), py - Float(filler))
                    point(Float(j), py)
                    point(Float(j + filler), py + Float(filler))
                }
            }
        }
    }
}
