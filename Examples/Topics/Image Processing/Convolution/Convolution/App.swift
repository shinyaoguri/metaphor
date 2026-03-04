import metaphor

@main
final class Convolution: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Convolution")
    }

    var img: MImage!
    var effect = 0
    let regionW = 120

    let kernels: [[[Float]]] = [
        [[0, 0, 0], [0, 1, 0], [0, 0, 0]],
        [[0, 0, 0], [0, 0.5, 0], [0, 0, 0]],
        [[0, 0, 0], [0, 2, 0], [0, 0, 0]],
        [[0, -1, 0], [-1, 5, -1], [0, -1, 0]],
        [[-1, -1, -1], [-1, 9, -1], [-1, -1, -1]],
        [[1.0 / 9, 1.0 / 9, 1.0 / 9], [1.0 / 9, 1.0 / 9, 1.0 / 9], [1.0 / 9, 1.0 / 9, 1.0 / 9]],
        [[0, 1, 0], [1, -4, 1], [0, 1, 0]],
        [[-2, -1, 0], [-1, 1, 1], [0, 1, 2]],
    ]

    let effectNames = [
        "Identity", "Darken", "Lighten", "Sharpen",
        "Sharpen More", "Box Blur", "Edge Detect", "Emboss",
    ]

    func setup() {
        noLoop()
        guard let generated = generateTestImage(Int(width), Int(height)) else { return }
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

    func convolve(_ x: Int, _ y: Int, _ kernel: [[Float]]) -> (UInt8, UInt8, UInt8) {
        var rTotal: Float = 0, gTotal: Float = 0, bTotal: Float = 0
        for i in 0..<3 {
            for j in 0..<3 {
                let xloc = max(0, min(Int(img.width) - 1, x + i - 1))
                let yloc = max(0, min(Int(img.height) - 1, y + j - 1))
                let loc = (yloc * Int(img.width) + xloc) * 4
                rTotal += Float(img.pixels[loc]) * kernel[i][j]
                gTotal += Float(img.pixels[loc + 1]) * kernel[i][j]
                bTotal += Float(img.pixels[loc + 2]) * kernel[i][j]
            }
        }
        return (
            UInt8(max(0, min(255, rTotal))),
            UInt8(max(0, min(255, gTotal))),
            UInt8(max(0, min(255, bTotal)))
        )
    }

    func draw() {
        image(img, 0, 0)

        img.loadPixels()
        guard let result = createImage(Int(img.width), Int(img.height)) else { return }
        result.loadPixels()

        // Copy original
        for i in 0..<img.pixels.count {
            result.pixels[i] = img.pixels[i]
        }

        let xstart = max(0, Int(mouseX) - regionW / 2)
        let ystart = max(0, Int(mouseY) - regionW / 2)
        let xend = min(Int(img.width), Int(mouseX) + regionW / 2)
        let yend = min(Int(img.height), Int(mouseY) + regionW / 2)

        for x in xstart..<xend {
            for y in ystart..<yend {
                let (r, g, b) = convolve(x, y, kernels[effect])
                let loc = (y * Int(img.width) + x) * 4
                result.pixels[loc] = r
                result.pixels[loc + 1] = g
                result.pixels[loc + 2] = b
                result.pixels[loc + 3] = 255
            }
        }
        result.updatePixels()
        image(result, 0, 0)

        fill(255)
        textSize(24)
        text(effectNames[effect], 4, 24)
    }

    func mousePressed() {
        effect = (effect + 1) % effectNames.count
        redraw()
    }

    func mouseMoved() { redraw() }
    func mouseDragged() { redraw() }
}
