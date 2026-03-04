import metaphor

@main
final class TextureTriangle: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "TextureTriangle")
    }

    var img: MImage!

    func setup() {
        let sz = 128
        img = createImage(sz, sz)
        img.loadPixels()
        for y in 0..<sz {
            for x in 0..<sz {
                let idx = (y * sz + x) * 4
                img.pixels[idx] = UInt8(x * 2 % 256)
                img.pixels[idx + 1] = UInt8((128 + y) % 256)
                img.pixels[idx + 2] = 200
                img.pixels[idx + 3] = 255
                }
        }
        img.updatePixels()
        noStroke()
    }

    func draw() {
        background(0)
        translate(width / 2, height / 2, 0)
        rotateY(map(mouseX, 0, width, -.pi, .pi))

        beginShape(.triangles)
        texture(img)
        vertex(-100, -100, 0)
        vertex(100, -40, 0)
        vertex(0, 100, 0)
        endShape()
    }
}
