import metaphor

// NOTE: Original uses a GLSL mask shader.
// This version uses CPU pixel-based masking.

@main
final class ImageMask: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ImageMask")
    }

    var srcImg: MImage!
    var displayImg: MImage!

    func setup() {
        let w = Int(width), h = Int(height)

        // Generate source image (leaf-like pattern)
        srcImg = createImage(w, h)
        srcImg.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let nx = Float(x) / Float(w)
                let ny = Float(y) / Float(h)
                srcImg.pixels[idx] = UInt8(max(0, min(255, Int(sin(nx * 12) * 60 + 90))))
                srcImg.pixels[idx+1] = UInt8(max(0, min(255, Int(cos(ny * 8) * 50 + 150))))
                srcImg.pixels[idx+2] = UInt8(max(0, min(255, Int(sin(nx * 6 + ny * 4) * 40 + 60))))
                srcImg.pixels[idx+3] = 255
            }
        }
        srcImg.updatePixels()

        displayImg = createImage(w, h)
    }

    func draw() {
        let w = Int(width), h = Int(height)
        let maskRadius: Float = 50

        srcImg.loadPixels()
        displayImg.loadPixels()

        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let dx = Float(x) - mouseX
                let dy = Float(y) - mouseY
                let d = sqrt(dx * dx + dy * dy)

                if d < maskRadius {
                    // Show source image inside mask
                    let fade = max(0, 1.0 - d / maskRadius)
                    displayImg.pixels[idx] = UInt8(Float(srcImg.pixels[idx]) * fade)
                    displayImg.pixels[idx+1] = UInt8(Float(srcImg.pixels[idx+1]) * fade)
                    displayImg.pixels[idx+2] = UInt8(Float(srcImg.pixels[idx+2]) * fade)
                } else {
                    // White background
                    displayImg.pixels[idx] = 255
                    displayImg.pixels[idx+1] = 255
                    displayImg.pixels[idx+2] = 255
                }
                displayImg.pixels[idx+3] = 255
            }
        }
        displayImg.updatePixels()
        image(displayImg, 0, 0)
    }
}
