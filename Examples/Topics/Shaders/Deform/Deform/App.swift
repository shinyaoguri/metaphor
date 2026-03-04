import metaphor

// NOTE: Original uses a GLSL deform shader.
// This version approximates the deformation using CPU pixel rendering.

@main
final class Deform: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Deform", width: 640, height: 360)
    }

    var tex: MImage!
    var displayImg: MImage!
    let texSize = 64
    let scale = 2

    func setup() {
        noStroke()

        // Generate a checkerboard texture
        tex = createImage(texSize, texSize)
        tex.loadPixels()
        for y in 0..<texSize {
            for x in 0..<texSize {
                let idx = (y * texSize + x) * 4
                let checker = ((x / 8) + (y / 8)) % 2 == 0
                let v: UInt8 = checker ? 200 : 80
                tex.pixels[idx] = v
                tex.pixels[idx + 1] = UInt8(checker ? 180 : 60)
                tex.pixels[idx + 2] = UInt8(checker ? 100 : 120)
                tex.pixels[idx + 3] = 255
            }
        }
        tex.updatePixels()

        displayImg = createImage(Int(width) / scale, Int(height) / scale)
    }

    func draw() {
        let w = displayImg.width, h = displayImg.height
        let t = Float(millis()) / 1000.0
        let mx = mouseX / width
        let my = mouseY / height

        tex.loadPixels()
        displayImg.loadPixels()

        for py in 0..<h {
            for px in 0..<w {
                let x = Float(px) / Float(w) * 2.0 - 1.0
                let y = Float(py) / Float(h) * 2.0 - 1.0

                let r = sqrt(x * x + y * y)
                let a = atan2(y, x)

                // Deformation
                let u = cos(a + sin(r * 3 + t)) / (r + 0.5 + mx)
                let v = sin(a + cos(r * 2 + t * 0.7)) / (r + 0.5 + my)

                // Wrap to tile coordinates
                let tx = ((Int(u * Float(texSize)) % texSize) + texSize) % texSize
                let ty = ((Int(v * Float(texSize)) % texSize) + texSize) % texSize

                let srcIdx = (ty * texSize + tx) * 4
                let dstIdx = (py * w + px) * 4
                displayImg.pixels[dstIdx] = tex.pixels[srcIdx]
                displayImg.pixels[dstIdx + 1] = tex.pixels[srcIdx + 1]
                displayImg.pixels[dstIdx + 2] = tex.pixels[srcIdx + 2]
                displayImg.pixels[dstIdx + 3] = 255
            }
        }
        displayImg.updatePixels()
        image(displayImg, 0, 0, width, height)
    }
}
