import metaphor

// NOTE: The original Processing example loads an image from a URL.
// metaphor's loadImage() works with local file paths.
// This example uses a generated image as a demonstration.

@main
final class LoadingImages: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Loading Images", width: 640, height: 360)
    }

    var img: MImage?

    func setup() {
        img = createImage(640, 72)
        guard let img = img else { return }
        img.loadPixels()
        for y in 0..<Int(img.height) {
            for x in 0..<Int(img.width) {
                let idx = (y * Int(img.width) + x) * 4
                img.pixels[idx] = UInt8(Float(x) / img.width * 100 + 50)
                img.pixels[idx + 1] = UInt8(Float(x) / img.width * 150 + 50)
                img.pixels[idx + 2] = 200
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
        noLoop()
    }

    func draw() {
        background(0)
        guard let img = img else { return }
        for i in 0..<5 {
            image(img, 0, img.height * Float(i))
        }
    }
}
