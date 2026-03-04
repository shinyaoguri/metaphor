import metaphor

@main
final class EdgeDetection: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "EdgeDetection")
    }

    var img: MImage!

    func setup() {
        noLoop()
        guard let generated = generateTestImage(Int(width) / 2, Int(height)) else { return }
        img = generated
    }

    func generateTestImage(_ w: Int, _ h: Int) -> MImage? {
        guard let img = createImage(w, h) else { return nil }
        img.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let nx = Float(x) / Float(w)
                let ny = Float(y) / Float(h)
                let cx = nx - 0.5, cy = ny - 0.5
                let d = sqrt(cx * cx + cy * cy)
                let base = (1.0 - d * 2) * 200 + sin(nx * 20) * 30 + cos(ny * 15) * 20
                let v = UInt8(max(0, min(255, Int(base))))
                img.pixels[idx] = v
                let greenVal = Float(v) * 0.8 + ny * 50
                img.pixels[idx + 1] = UInt8(max(0, min(255, Int(greenVal))))
                let blueVal = Float(v) * 0.6 + nx * 80
                img.pixels[idx + 2] = UInt8(max(0, min(255, Int(blueVal))))
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
        return img
    }

    func draw() {
        background(0)
        image(img, 0, 0)

        let kernel: [[Float]] = [[-1, -1, -1], [-1, 8, -1], [-1, -1, -1]]

        img.loadPixels()
        let w = Int(img.width), h = Int(img.height)
        guard let edgeImg = createImage(w, h) else { return }
        edgeImg.loadPixels()

        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                var sum: Float = 128 // Offset from gray
                for ky in -1...1 {
                    for kx in -1...1 {
                        let pos = ((y + ky) * w + (x + kx)) * 4
                        // Convert to grayscale
                        let rComp = Float(img.pixels[pos]) * 0.299
                        let gComp = Float(img.pixels[pos + 1]) * 0.587
                        let bComp = Float(img.pixels[pos + 2]) * 0.114
                        let gray = rComp + gComp + bComp
                        sum += kernel[ky + 1][kx + 1] * gray
                    }
                }
                let v = UInt8(max(0, min(255, sum)))
                let outIdx = (y * w + x) * 4
                edgeImg.pixels[outIdx] = v
                edgeImg.pixels[outIdx + 1] = v
                edgeImg.pixels[outIdx + 2] = v
                edgeImg.pixels[outIdx + 3] = 255
            }
        }
        edgeImg.updatePixels()
        image(edgeImg, width / 2, 0)
    }
}
