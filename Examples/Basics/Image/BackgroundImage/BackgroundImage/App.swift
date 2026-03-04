import metaphor

@main
final class BackgroundImage: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Background Image", width: 640, height: 360)
    }

    var bg: MImage?

    func setup() {
        bg = createImage(640, 360)
        guard let bg = bg else { return }
        bg.loadPixels()
        for y in 0..<Int(bg.height) {
            for x in 0..<Int(bg.width) {
                let idx = (y * Int(bg.width) + x) * 4
                bg.pixels[idx] = UInt8(Float(x) / bg.width * 180)
                bg.pixels[idx + 1] = UInt8(Float(y) / bg.height * 150)
                bg.pixels[idx + 2] = 130
                bg.pixels[idx + 3] = 255
            }
        }
        bg.updatePixels()
    }

    func draw() {
        guard let bg = bg else { return }
        image(bg, 0, 0)
        let lineX = Float(frameCount % Int(width))
        stroke(255)
        line(lineX, 0, lineX, height)
    }
}
