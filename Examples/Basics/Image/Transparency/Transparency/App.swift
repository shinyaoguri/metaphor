import metaphor

@main
final class Transparency: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Transparency")
    }

    var img: MImage?
    var offset: Float = 0
    var easing: Float = 0.05

    func setup() {
        // Generate a sample image (replaces moonwalk.jpg)
        img = createImage(640, 360)
        guard let img = img else { return }
        img.loadPixels()
        for y in 0..<Int(img.height) {
            for x in 0..<Int(img.width) {
                let idx = (y * Int(img.width) + x) * 4
                img.pixels[idx] = UInt8(Float(x) / img.width * 200)
                img.pixels[idx + 1] = UInt8(100)
                img.pixels[idx + 2] = UInt8(Float(y) / img.height * 255)
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
    }

    func draw() {
        background(0)
        guard let img = img else { return }
        let dx = (mouseX - img.width / 2) - offset
        offset += dx * easing

        tint(255)
        image(img, 0, 0)

        tint(255.0, 127.0)
        image(img, offset, height / 2 - img.height / 2)
    }
}
