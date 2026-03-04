import metaphor

@main
final class Blur: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Blur", width: 640, height: 360)
    }

    var img: MImage!

    func setup() {
        noLoop()
        img = generateTestImage(Int(width) / 2, Int(height))
    }

    func generateTestImage(_ w: Int, _ h: Int) -> MImage {
        let img = createImage(w, h)
        img.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let nx = Float(x) / Float(w)
                let ny = Float(y) / Float(h)
                let cx = nx - 0.5, cy = ny - 0.5
                let d = sqrt(cx * cx + cy * cy)
                let base = (1.0 - d * 2) * 200 + sin(nx * 20) * 30 + cos(ny * 15) * 20
                let v = UInt8(clamped: Int(max(0, min(255, base))))
                img.pixels[idx] = v
                img.pixels[idx + 1] = UInt8(clamped: Int(max(0, min(255, Float(v) * 0.8 + ny * 50))))
                img.pixels[idx + 2] = UInt8(clamped: Int(max(0, min(255, Float(v) * 0.6 + nx * 80))))
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
        return img
    }

    func draw() {
        background(0)
        image(img, 0, 0)

        let v: Float = 1.0 / 9.0
        let kernel: [[Float]] = [[v, v, v], [v, v, v], [v, v, v]]

        img.loadPixels()
        let w = img.width
        let h = img.height
        let blurImg = createImage(w, h)
        blurImg.loadPixels()

        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
                for ky in -1...1 {
                    for kx in -1...1 {
                        let pos = ((y + ky) * w + (x + kx)) * 4
                        sumR += kernel[ky + 1][kx + 1] * Float(img.pixels[pos])
                        sumG += kernel[ky + 1][kx + 1] * Float(img.pixels[pos + 1])
                        sumB += kernel[ky + 1][kx + 1] * Float(img.pixels[pos + 2])
                    }
                }
                let outIdx = (y * w + x) * 4
                blurImg.pixels[outIdx] = UInt8(max(0, min(255, sumR)))
                blurImg.pixels[outIdx + 1] = UInt8(max(0, min(255, sumG)))
                blurImg.pixels[outIdx + 2] = UInt8(max(0, min(255, sumB)))
                blurImg.pixels[outIdx + 3] = 255
            }
        }
        blurImg.updatePixels()
        image(blurImg, width / 2, 0)
    }
}
