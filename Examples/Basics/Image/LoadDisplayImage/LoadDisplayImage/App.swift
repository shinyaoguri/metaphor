import metaphor

@main
final class LoadDisplayImage: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Load Display Image")
    }

    var img: MImage?

    func setup() {
        // Generate a sample image (replaces moonwalk.jpg)
        img = createImage(320, 240)
        guard let img = img else { return }
        img.loadPixels()
        for y in 0..<Int(img.height) {
            for x in 0..<Int(img.width) {
                let idx = (y * Int(img.width) + x) * 4
                let cx = Float(x) / img.width
                let cy = Float(y) / img.height
                img.pixels[idx] = UInt8(cx * 255)
                img.pixels[idx + 1] = UInt8((1 - cy) * 200)
                img.pixels[idx + 2] = UInt8(cy * cx * 255)
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
        noLoop()
    }

    func draw() {
        background(0)
        guard let img = img else { return }
        image(img, 0, 0)
        image(img, img.width, 0, img.width / 2, img.height / 2)
    }
}
