import metaphor

@main final class NoiseField: Sketch {
    var config: SketchConfig { SketchConfig(title: "Noise Field") }

    func draw() {
        background(Color(gray: 0.02))

        let spacing: Float = 24
        let lineLength: Float = spacing * 0.8
        let noiseScale: Float = 0.008
        let timeScale: Float = 0.15

        let cols = Int(width / spacing) + 1
        let rows = Int(height / spacing) + 1

        strokeWeight(1.5)

        for row in 0..<rows {
            for col in 0..<cols {
                let x = Float(col) * spacing + spacing * 0.5
                let y = Float(row) * spacing + spacing * 0.5

                let noiseVal = noise(
                    x * noiseScale,
                    y * noiseScale,
                    time * timeScale
                )

                let angle = noiseVal * Float.pi * 4.0

                // Map noise to hue for coloring
                let hue = (noiseVal + time * 0.02).truncatingRemainder(dividingBy: 1.0)
                let brightness: Float = 0.6 + noiseVal * 0.4
                let color = Color(hue: hue, saturation: 0.7, brightness: brightness, alpha: 0.85)
                stroke(color)

                let dx = cos(angle) * lineLength * 0.5
                let dy = sin(angle) * lineLength * 0.5

                line(x - dx, y - dy, x + dx, y + dy)
            }
        }
    }
}
