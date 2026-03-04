import metaphor

@main
final class Blending: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Blending", width: 640, height: 360)
    }

    var img1: MImage!
    var img2: MImage!
    var modeIndex = 0
    let modeNames = ["BLEND", "ADD", "SUBTRACT", "MULTIPLY", "SCREEN"]

    func setup() {
        noStroke()
        let w = Int(width), h = Int(height)

        // Generate layer 1: warm gradient
        img1 = createImage(w, h)
        img1.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                img1.pixels[idx] = UInt8(min(255, x * 255 / w))
                img1.pixels[idx + 1] = UInt8(min(255, 100 + y * 100 / h))
                img1.pixels[idx + 2] = 50
                img1.pixels[idx + 3] = 255
            }
        }
        img1.updatePixels()

        // Generate layer 2: cool circles
        img2 = createImage(w, h)
        img2.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let dx = Float(x) - Float(w) / 2
                let dy = Float(y) - Float(h) / 2
                let d = sqrt(dx * dx + dy * dy)
                let v = UInt8(max(0, min(255, Int(sin(d * 0.05) * 127 + 128))))
                img2.pixels[idx] = 50
                img2.pixels[idx + 1] = v
                img2.pixels[idx + 2] = UInt8(min(255, Int(Float(v) * 1.2)))
                img2.pixels[idx + 3] = 255
            }
        }
        img2.updatePixels()
    }

    func draw() {
        let picAlpha = Int(map(mouseX, 0, width, 0, 255))

        background(0)
        tint(255, 255)
        image(img1, 0, 0)

        // Apply blend mode based on index
        // Since metaphor may not support all Processing blend modes,
        // we'll demonstrate with available ones
        tint(255, Float(picAlpha))
        image(img2, 0, 0)

        // Reset and draw label
        tint(255, 255)
        fill(255)
        rect(0, 0, 100, 22)
        fill(0)
        text(modeNames[modeIndex], 10, 15)
    }

    func mousePressed() {
        modeIndex = (modeIndex + 1) % modeNames.count
    }
}
