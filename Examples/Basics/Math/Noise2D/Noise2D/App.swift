import metaphor

@main
final class Noise2D: Sketch {
    let increment: Float = 0.02
    var img: MImage?
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Noise 2D") }

    func setup() {
        img = createImage(Int(width), Int(height))
    }

    func draw() {
        guard let img = img else { return }
        img.loadPixels()

        let detail = map(mouseX, 0, width, 0.1, 0.6)
        noiseDetail(octaves: 8, falloff: detail)

        let w = Int(width)
        let h = Int(height)
        var xoff: Float = 0
        for x in 0..<w {
            xoff += increment
            var yoff: Float = 0
            for y in 0..<h {
                yoff += increment
                let bright = UInt8(clamping: Int(noise(xoff, yoff) * 255))
                let idx = (x + y * w) * 4
                img.pixels[idx] = bright
                img.pixels[idx + 1] = bright
                img.pixels[idx + 2] = bright
                img.pixels[idx + 3] = 255
            }
        }

        img.updatePixels()
        image(img, 0, 0)
    }
}
