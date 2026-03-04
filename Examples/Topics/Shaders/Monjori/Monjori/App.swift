import metaphor

// NOTE: Original uses a GLSL fragment shader (monjori.glsl).
// This version approximates the effect using CPU pixel rendering.

@main
final class Monjori: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Monjori", width: 640, height: 360)
    }

    var img: MImage!
    let scale = 4  // Render at 1/4 resolution for performance

    func setup() {
        noStroke()
        img = createImage(Int(width) / scale, Int(height) / scale)
    }

    func draw() {
        let w = img.width, h = img.height
        let t = Float(millis()) / 1000.0

        img.loadPixels()
        for py in 0..<h {
            for px in 0..<w {
                var x = Float(px) / Float(w) * 2.0 - 1.0
                var y = Float(py) / Float(h) * 2.0 - 1.0
                x *= Float(w) / Float(h)  // aspect ratio

                // Simplified Monjori-style deformation
                let a = x * x + y * y
                var v: Float = 0
                for i in 0..<8 {
                    let fi = Float(i) + 1.0
                    let xx = x + cos(t * 0.3 + fi * 0.7) * fi
                    let yy = y + sin(t * 0.5 + fi * 0.5) * fi
                    v += sin(xx * xx + yy * yy + t) / fi
                }
                v = abs(v)

                let r = UInt8(max(0, min(255, Int(sin(v * 3.0) * 127 + 128))))
                let g = UInt8(max(0, min(255, Int(sin(v * 5.0 + 2.0) * 127 + 128))))
                let b = UInt8(max(0, min(255, Int(sin(v * 7.0 + 4.0) * 127 + 128))))

                let idx = (py * w + px) * 4
                img.pixels[idx] = r
                img.pixels[idx + 1] = g
                img.pixels[idx + 2] = b
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
        image(img, 0, 0, width, height)
    }
}
