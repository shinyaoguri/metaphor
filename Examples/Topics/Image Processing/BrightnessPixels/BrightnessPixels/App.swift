import metaphor

@main
final class BrightnessPixels: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "BrightnessPixels", width: 640, height: 360)
    }

    var srcImg: MImage!
    var displayImg: MImage!

    func setup() {
        frameRate(30)
        let w = Int(width), h = Int(height)

        srcImg = createImage(w, h)
        srcImg.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let nx = Float(x) / Float(w)
                let ny = Float(y) / Float(h)
                let cx = nx - 0.4, cy = ny - 0.4
                let d = sqrt(cx * cx + cy * cy)
                let v = UInt8(max(0, min(255, Int((1.0 - d * 1.5) * 180 + sin(nx * 30) * 20))))
                srcImg.pixels[idx] = v
                srcImg.pixels[idx + 1] = v
                srcImg.pixels[idx + 2] = v
                srcImg.pixels[idx + 3] = 255
            }
        }
        srcImg.updatePixels()

        displayImg = createImage(w, h)
    }

    func draw() {
        let w = Int(width), h = Int(height)
        srcImg.loadPixels()
        displayImg.loadPixels()

        for y in 0..<h {
            for x in 0..<w {
                let loc = (y * w + x) * 4
                let r = Float(srcImg.pixels[loc])
                let maxDist: Float = 50
                let dx = Float(x) - mouseX
                let dy = Float(y) - mouseY
                let d = sqrt(dx * dx + dy * dy)
                let adjust = 255 * (maxDist - d) / maxDist
                let newR = max(0, min(255, r + adjust))
                let v = UInt8(newR)
                displayImg.pixels[loc] = v
                displayImg.pixels[loc + 1] = v
                displayImg.pixels[loc + 2] = v
                displayImg.pixels[loc + 3] = 255
            }
        }
        displayImg.updatePixels()
        image(displayImg, 0, 0)
    }
}
