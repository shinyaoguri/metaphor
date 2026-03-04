import metaphor

@main
final class CreateImage: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Create Image")
    }

    var img: MImage?

    func setup() {
        img = createImage(230, 230)
        guard let img = img else { return }
        img.loadPixels()
        let totalPixels = Int(img.width) * Int(img.height)
        for i in 0..<totalPixels {
            let a = UInt8(map(Float(i), 0, Float(totalPixels), 255, 0))
            let idx = i * 4
            img.pixels[idx] = 0
            img.pixels[idx + 1] = 153
            img.pixels[idx + 2] = 204
            img.pixels[idx + 3] = a
        }
        img.updatePixels()
    }

    func draw() {
        background(0)
        guard let img = img else { return }
        image(img, 90, 80)
        image(img, mouseX - img.width / 2, mouseY - img.height / 2)
    }
}
