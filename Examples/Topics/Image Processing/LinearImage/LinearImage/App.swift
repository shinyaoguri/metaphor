import metaphor

@main
final class LinearImage: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "LinearImage")
    }

    var img: MImage!
    var displayImg: MImage!
    var signal: Float = 0
    var direction: Int = 1

    func setup() {
        stroke(255)
        let w = Int(width), h = Int(height)

        img = createImage(w, h)
        img.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let nx = Float(x) / Float(w)
                let ny = Float(y) / Float(h)
                // Sea-like gradient
                let r = UInt8(max(0, min(255, Int(sin(ny * .pi) * 50 + nx * 30))))
                let g = UInt8(max(0, min(255, Int(sin(ny * .pi) * 100 + 80))))
                let b = UInt8(max(0, min(255, Int(150 + sin(nx * 10 + ny * 5) * 50))))
                img.pixels[idx] = r
                img.pixels[idx + 1] = g
                img.pixels[idx + 2] = b
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()

        displayImg = createImage(w, h)
    }

    func draw() {
        let w = Int(width), h = Int(height)

        if signal > Float(h - 1) || signal < 0 {
            direction *= -1
        }

        if isMousePressed {
            signal = abs(mouseY).truncatingRemainder(dividingBy: Float(h))
        } else {
            signal += 0.3 * Float(direction)
        }

        if isKeyPressed {
            image(img, 0, 0)
            line(0, signal, Float(w), signal)
        } else {
            // Fill entire display with the single scanned row
            let signalRow = max(0, min(h - 1, Int(signal)))
            img.loadPixels()
            displayImg.loadPixels()
            for y in 0..<h {
                for x in 0..<w {
                    let srcIdx = (signalRow * w + x) * 4
                    let dstIdx = (y * w + x) * 4
                    displayImg.pixels[dstIdx] = img.pixels[srcIdx]
                    displayImg.pixels[dstIdx + 1] = img.pixels[srcIdx + 1]
                    displayImg.pixels[dstIdx + 2] = img.pixels[srcIdx + 2]
                    displayImg.pixels[dstIdx + 3] = 255
                }
            }
            displayImg.updatePixels()
            image(displayImg, 0, 0)
        }
    }
}
