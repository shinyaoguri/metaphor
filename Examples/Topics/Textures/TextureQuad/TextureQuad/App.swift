import metaphor

@main
final class TextureQuad: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "TextureQuad")
    }

    var img: MImage!

    func setup() {
        let sz = 128
        img = createImage(sz, sz)
        img.loadPixels()
        for y in 0..<sz {
            for x in 0..<sz {
                let idx = (y * sz + x) * 4
                img.pixels[idx] = UInt8((x + y) % 256)
                img.pixels[idx + 1] = UInt8(x * 2 % 256)
                img.pixels[idx + 2] = UInt8(y * 2 % 256)
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
        noStroke()
    }

    func draw() {
        background(0)
        translate(width / 2, height / 2)
        rotateY(map(mouseX, 0, width, -.pi, .pi))
        rotateZ(.pi / 6)

        beginShape3D(.triangles)
        // NOTE: texture() has no effect on a custom 3D shape yet — the 3D vertex format
        // has no UV channel, so this renders with the current fill (metaphor #387).
        texture(img)
        vertex(-100, -100, 0)
        vertex(100, -100, 0)
        vertex(100, 100, 0)
        vertex(-100, -100, 0)
        vertex(100, 100, 0)
        vertex(-100, 100, 0)
        endShape3D()
    }
}
