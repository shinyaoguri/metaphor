import metaphor

// NOTE: Original uses a GLSL fragment shader (nebula.glsl).
// This version approximates the effect using CPU pixel rendering.

@main
final class Nebula: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Nebula", width: 640, height: 360)
    }

    var img: MImage!
    let scale = 4

    func setup() {
        noStroke()
        img = createImage(Int(width) / scale, Int(height) / scale)
    }

    func draw() {
        let w = img.width, h = img.height
        let t = Float(millis()) / 500.0

        img.loadPixels()
        for py in 0..<h {
            for px in 0..<w {
                let x = Float(px) / Float(w) * 2.0 - 1.0
                let y = Float(py) / Float(h) * 2.0 - 1.0

                // Simplified nebula effect with layered noise
                var r: Float = 0, g: Float = 0, b: Float = 0
                for i in 1...5 {
                    let fi = Float(i)
                    let s = fi * 0.5
                    let nx = x * s + t * 0.1 * fi
                    let ny = y * s + t * 0.15 * fi
                    let v = sin(nx * 3 + sin(ny * 2 + t * fi * 0.1))
                        * cos(ny * 2 + cos(nx * 3 + t * 0.2))
                    r += v * 0.15 * (1.0 + sin(fi))
                    g += v * 0.1 * (1.0 + cos(fi * 2))
                    b += v * 0.2 * (1.0 + sin(fi * 3))
                }

                let rv = UInt8(max(0, min(255, Int((r * 0.5 + 0.3) * 255))))
                let gv = UInt8(max(0, min(255, Int((g * 0.3 + 0.1) * 255))))
                let bv = UInt8(max(0, min(255, Int((b * 0.5 + 0.4) * 255))))

                let idx = (py * w + px) * 4
                img.pixels[idx] = rv
                img.pixels[idx + 1] = gv
                img.pixels[idx + 2] = bv
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
        image(img, 0, 0, width, height)
    }
}
