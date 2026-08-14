import Foundation
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
        guard
            let path = Bundle.module.path(forResource: "leaves", ofType: "jpg", inDirectory: "Resources"),
            let loaded = try? loadImage(path)
        else { return }
        img = loaded
        let w = Int(img.width), h = Int(img.height)

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
