import metaphor

@main
final class Alphamask: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Alpha Mask", width: 640, height: 360)
    }

    var img: MImage?

    func setup() {
        let src = createImage(200, 200)
        guard let src = src else { return }
        src.loadPixels()
        // Fill with gradient colors
        for y in 0..<Int(src.height) {
            for x in 0..<Int(src.width) {
                let idx = (y * Int(src.width) + x) * 4
                src.pixels[idx] = UInt8(Float(x) / src.width * 255)
                src.pixels[idx + 1] = 100
                src.pixels[idx + 2] = UInt8(Float(y) / src.height * 255)
                src.pixels[idx + 3] = 255
            }
        }
        // Apply circular mask
        let cx = src.width / 2
        let cy = src.height / 2
        let r = min(src.width, src.height) / 2
        for y in 0..<Int(src.height) {
            for x in 0..<Int(src.width) {
                let dx = Float(x) - cx
                let dy = Float(y) - cy
                let dist = sqrt(dx * dx + dy * dy)
                let alpha: UInt8 = dist < r ? 255 : 0
                let idx = (y * Int(src.width) + x) * 4
                src.pixels[idx + 3] = alpha
            }
        }
        src.updatePixels()
        img = src
    }

    func draw() {
        background(0)
        guard let img = img else { return }
        image(img, width / 2 - img.width / 2, height / 2 - img.height / 2)
        image(img, mouseX - img.width / 2, mouseY - img.height / 2)
    }
}
