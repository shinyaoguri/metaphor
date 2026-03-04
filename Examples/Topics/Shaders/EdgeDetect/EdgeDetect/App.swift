import metaphor

// NOTE: Original uses a GLSL edge detection shader.
// This version uses CPU convolution as approximation.

@main
final class EdgeDetect: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "EdgeDetect")
    }

    var img: MImage!
    var edgeImg: MImage!
    var enabled = true

    func setup() {
        noLoop()
        let w = Int(width), h = Int(height)

        // Generate leaf-like image
        img = createImage(w, h)
        img.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let nx = Float(x) / Float(w)
                let ny = Float(y) / Float(h)
                let leaf = sin(nx * 12 + ny * 8) * cos(nx * 6 - ny * 10)
                let r = UInt8(max(0, min(255, Int(leaf * 60 + 80))))
                let g = UInt8(max(0, min(255, Int(leaf * 40 + 140))))
                let b = UInt8(max(0, min(255, Int(leaf * 30 + 50))))
                img.pixels[idx] = r; img.pixels[idx + 1] = g
                img.pixels[idx + 2] = b; img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()

        // Compute edge detection
        let kernel: [[Float]] = [[-1, -1, -1], [-1, 8, -1], [-1, -1, -1]]
        edgeImg = createImage(w, h)
        img.loadPixels()
        edgeImg.loadPixels()
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                var sum: Float = 128
                for ky in -1...1 {
                    for kx in -1...1 {
                        let pos = ((y + ky) * w + (x + kx)) * 4
                        let gray = Float(img.pixels[pos]) * 0.3
                            + Float(img.pixels[pos + 1]) * 0.59
                            + Float(img.pixels[pos + 2]) * 0.11
                        sum += kernel[ky + 1][kx + 1] * gray
                    }
                }
                let v = UInt8(max(0, min(255, sum)))
                let idx = (y * w + x) * 4
                edgeImg.pixels[idx] = v; edgeImg.pixels[idx + 1] = v
                edgeImg.pixels[idx + 2] = v; edgeImg.pixels[idx + 3] = 255
            }
        }
        edgeImg.updatePixels()
    }

    func draw() {
        if enabled {
            image(edgeImg, 0, 0)
        } else {
            image(img, 0, 0)
        }
    }

    func mousePressed() {
        enabled = !enabled
        redraw()
    }
}
