import metaphor
import Foundation

@main
final class Alphamask: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Alpha Mask")
    }

    var img: MImage?

    func setup() {
        guard let imgPath = Bundle.module.path(forResource: "moonwalk", ofType: "jpg", inDirectory: "Resources"),
              let maskPath = Bundle.module.path(forResource: "mask", ofType: "jpg", inDirectory: "Resources"),
              let src = try? loadImage(imgPath),
              let maskImg = try? loadImage(maskPath) else { return }

        // Apply the mask: use maskImg's brightness as src's alpha
        src.loadPixels()
        maskImg.loadPixels()
        let w = Int(src.width)
        let h = Int(src.height)
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                // mask pixels are RGBA after loadPixels; use red channel as alpha
                let maskAlpha = maskImg.pixels[idx]
                src.pixels[idx + 3] = maskAlpha
            }
        }
        src.updatePixels()
        img = src
        imageMode(.center)
    }

    func draw() {
        background(0, 102, 153)
        guard let img = img else { return }
        image(img, width / 2, height / 2)
        image(img, mouseX, mouseY)
    }
}
