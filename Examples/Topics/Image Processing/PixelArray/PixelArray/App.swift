import metaphor

@main
final class PixelArray: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "PixelArray", width: 640, height: 360)
    }

    var img: MImage!
    var direction: Int = 1
    var signal: Float = 0

    func setup() {
        noFill()
        stroke(255)
        frameRate(30)

        let w = Int(width), h = Int(height)
        img = createImage(w, h)
        img.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let nx = Float(x) / Float(w)
                let ny = Float(y) / Float(h)
                let r = UInt8(max(0, min(255, Int(sin(ny * .pi) * 80 + nx * 100 + 50))))
                let g = UInt8(max(0, min(255, Int(cos(nx * .pi * 2) * 60 + 100))))
                let b = UInt8(max(0, min(255, Int(150 + sin(nx * 10 + ny * 5) * 50))))
                img.pixels[idx] = r; img.pixels[idx + 1] = g
                img.pixels[idx + 2] = b; img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
    }

    func draw() {
        let total = Float(img.width * img.height)
        if signal > total - 1 || signal < 0 {
            direction *= -1
        }

        if isMousePressed {
            let mx = Int(constrain(mouseX, 0, Float(img.width - 1)))
            let my = Int(constrain(mouseY, 0, Float(img.height - 1)))
            signal = Float(my * img.width + mx)
        } else {
            signal += 0.33 * Float(direction)
        }

        let sx = Int(signal) % img.width
        let sy = Int(signal) / img.width

        if isKeyPressed {
            image(img, 0, 0)
            point(Float(sx), Float(sy))
            rect(Float(sx) - 5, Float(sy) - 5, 10, 10)
        } else {
            img.loadPixels()
            let clampedSy = max(0, min(img.height - 1, sy))
            let clampedSx = max(0, min(img.width - 1, sx))
            let idx = (clampedSy * img.width + clampedSx) * 4
            let r = Float(img.pixels[idx])
            let g = Float(img.pixels[idx + 1])
            let b = Float(img.pixels[idx + 2])
            background(r, g, b)
        }
    }
}
