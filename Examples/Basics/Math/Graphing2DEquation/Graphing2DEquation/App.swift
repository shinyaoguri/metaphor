import metaphor

@main
final class Graphing2DEquation: Sketch {
    var img: MImage?
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Graphing 2D Equation") }

    func setup() {
        img = createImage(Int(width), Int(height))
    }

    func draw() {
        guard let img = img else { return }
        img.loadPixels()

        let pw = Int(width)
        let ph = Int(height)
        let n = (mouseX * 10) / width
        let w: Float = 16; let h: Float = 16
        let dx = w / width; let dy = h / height
        var x = -w / 2
        for i in 0..<pw {
            var y = -h / 2
            for j in 0..<ph {
                let r = sqrt(x * x + y * y)
                let theta = atan2(y, x)
                let val = sin(n * cos(r) + 5 * theta)
                let gray = UInt8(clamping: Int((val + 1.0) * 255.0 / 2.0))
                let idx = (i + j * pw) * 4
                img.pixels[idx] = gray
                img.pixels[idx + 1] = gray
                img.pixels[idx + 2] = gray
                img.pixels[idx + 3] = 255
                y += dy
            }
            x += dx
        }

        img.updatePixels()
        image(img, 0, 0)
    }
}
