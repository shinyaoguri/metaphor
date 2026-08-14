import Foundation
import metaphor

@main
final class Blur: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Blur")
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

        let v: Float = 1.0 / 9.0
        let kernel: [[Float]] = [[v, v, v], [v, v, v], [v, v, v]]

        img.loadPixels()
        let w = Int(img.width)
        let h = Int(img.height)
        guard let blurImg = createImage(w, h) else { return }
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
