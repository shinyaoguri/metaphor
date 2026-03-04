import metaphor

// NOTE: Original uses an iq raymarching GLSL shader (landscape.glsl).
// This version creates a simplified terrain visualization using noise.

@main
final class Landscape: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Landscape", width: 640, height: 360)
    }

    func setup() {
        noStroke()
    }

    func draw() {
        background(135, 180, 220)  // Sky
        let t = Float(millis()) / 5000.0

        // Draw terrain as horizontal scan lines
        for y in stride(from: Int(height / 2), to: Int(height), by: 2) {
            let ny = Float(y - Int(height / 2)) / Float(height / 2)  // 0 to 1
            let depth = 1.0 / (ny + 0.01)

            for x in stride(from: 0, to: Int(width), by: 2) {
                let nx = Float(x) / width

                // Terrain height using layered sine
                var h: Float = 0
                h += sin((nx * 5 + t) * depth * 0.5) * 20
                h += sin((nx * 13 + t * 0.7) * depth * 0.3) * 10
                h += cos((nx * 7 - t * 0.3) * depth * 0.4) * 15

                let screenY = Float(y) - h * ny

                // Color based on height and depth
                let fog = min(1.0, ny * 0.5 + 0.3)
                let green = UInt8(max(0, min(255, Int(80 + h * 2 * fog))))
                let brown = UInt8(max(0, min(255, Int(60 + h * fog))))

                fill(Float(brown) * (1 - fog * 0.3), Float(green), Float(brown) * 0.5, 255)
                rect(Float(x), screenY, 2, Float(y) - screenY + 2)
            }
        }

        // Sun
        fill(255, 240, 200)
        ellipse(width * 0.7, height * 0.15, 40, 40)
    }
}
