import Foundation
import metaphor

@main
final class EdgeDetection: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "EdgeDetection")
    }

    var img: MImage!

    func setup() {
        noLoop()
        guard
            let path = Bundle.module.path(forResource: "moon", ofType: "jpg", inDirectory: "Resources"),
            let loaded = try? loadImage(path)
        else { return }
        img = loaded
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
