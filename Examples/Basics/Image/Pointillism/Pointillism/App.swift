import metaphor

@main
final class Pointillism: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Pointillism")
    }

    var img: MImage?
    var smallPoint: Float = 4
    var largePoint: Float = 40

    func setup() {
        img = createImage(640, 360)
        guard let img = img else { return }
        img.loadPixels()
        for y in 0..<Int(img.height) {
            for x in 0..<Int(img.width) {
                let idx = (y * Int(img.width) + x) * 4
                let nx = Float(x) / img.width * 4
                let ny = Float(y) / img.height * 4
                img.pixels[idx] = UInt8(sin(nx * 3.14) * 127 + 128)
                img.pixels[idx + 1] = UInt8(cos(ny * 2.5) * 127 + 128)
                img.pixels[idx + 2] = UInt8(sin((nx + ny) * 2) * 100 + 100)
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
        noStroke()
        background(255)
    }

    func draw() {
        guard let img = img else { return }
        let pointillize = map(mouseX, 0, width, smallPoint, largePoint)
        let x = Float.random(in: 0..<img.width)
        let y = Float.random(in: 0..<img.height)
        let c = img.get(Int(x), Int(y))
        fill(c.r * 255, c.g * 255, c.b * 255, 128)
        ellipse(x, y, pointillize, pointillize)
    }
}
