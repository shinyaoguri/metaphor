import metaphor

@main
final class Histogram: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Histogram", width: 640, height: 360)
    }

    func setup() {
        noLoop()
    }

    func draw() {
        let w = Int(width), h = Int(height)

        // Generate image
        let img = createImage(w, h)
        img.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let nx = Float(x) / Float(w)
                let ny = Float(y) / Float(h)
                let v = UInt8(max(0, min(255, Int(sin(nx * 8) * cos(ny * 6) * 127 + 128))))
                let g = UInt8(max(0, min(255, Int(Float(v) * 0.8 + ny * 50))))
                let b = UInt8(max(0, min(255, Int(Float(v) * 0.6 + nx * 100))))
                img.pixels[idx] = v
                img.pixels[idx + 1] = g
                img.pixels[idx + 2] = b
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()

        image(img, 0, 0)

        // Calculate histogram
        var hist = [Int](repeating: 0, count: 256)
        img.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let r = Float(img.pixels[idx])
                let g = Float(img.pixels[idx + 1])
                let b = Float(img.pixels[idx + 2])
                let bright = Int(r * 0.299 + g * 0.587 + b * 0.114)
                let clamped = max(0, min(255, bright))
                hist[clamped] += 1
            }
        }

        let histMax = hist.max() ?? 1

        stroke(255)
        for i in stride(from: 0, to: w, by: 2) {
            let which = Int(Float(i) / Float(w) * 255)
            let clamped = max(0, min(255, which))
            let yPos = Int(Float(hist[clamped]) / Float(histMax) * Float(h))
            line(Float(i), Float(h), Float(i), Float(h - yPos))
        }
    }
}
