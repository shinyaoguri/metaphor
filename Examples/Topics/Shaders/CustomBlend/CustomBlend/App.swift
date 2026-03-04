import metaphor

// NOTE: Original uses GLSL blend shaders (dodge, burn, overlay, difference).
// This version approximates blend modes using CPU pixel operations.

@main
final class CustomBlend: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "CustomBlend")
    }

    var destImg: MImage!
    var srcImg: MImage!

    func setup() {
        noLoop()
        noStroke()
        let w = Int(width) / 2, h = Int(height) / 2

        // Generate destination image (leaf-like)
        destImg = createImage(w, h)
        destImg.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let nx = Float(x) / Float(w)
                let ny = Float(y) / Float(h)
                destImg.pixels[idx] = UInt8(max(0, min(255, Int(sin(nx * 10) * 60 + 100))))
                destImg.pixels[idx + 1] = UInt8(max(0, min(255, Int(cos(ny * 8) * 40 + 140))))
                destImg.pixels[idx + 2] = UInt8(max(0, min(255, Int(sin(nx * 5 + ny * 7) * 30 + 60))))
                destImg.pixels[idx + 3] = 255
            }
        }
        destImg.updatePixels()

        // Generate source image (moonwalk-like)
        srcImg = createImage(w, h)
        srcImg.loadPixels()
        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let nx = Float(x) / Float(w)
                let ny = Float(y) / Float(h)
                let d = sqrt((nx - 0.5) * (nx - 0.5) + (ny - 0.5) * (ny - 0.5))
                let v = UInt8(max(0, min(255, Int((1.0 - d * 2) * 200 + 30))))
                srcImg.pixels[idx] = v
                srcImg.pixels[idx + 1] = UInt8(max(0, min(255, Int(Float(v) * 0.9))))
                srcImg.pixels[idx + 2] = UInt8(max(0, min(255, Int(Float(v) * 0.7))))
                srcImg.pixels[idx + 3] = 255
            }
        }
        srcImg.updatePixels()
    }

    func blendImages(_ mode: String) -> MImage {
        let w = Int(destImg.width), h = Int(destImg.height)
        let result = createImage(w, h)!
        destImg.loadPixels()
        srcImg.loadPixels()
        result.loadPixels()

        for y in 0..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                let dr = Float(destImg.pixels[idx]) / 255
                let dg = Float(destImg.pixels[idx+1]) / 255
                let db = Float(destImg.pixels[idx+2]) / 255
                let sr = Float(srcImg.pixels[idx]) / 255
                let sg = Float(srcImg.pixels[idx+1]) / 255
                let sb = Float(srcImg.pixels[idx+2]) / 255

                var r: Float, g: Float, b: Float
                switch mode {
                case "dodge":
                    r = dr / max(1.0 - sr, 0.001)
                    g = dg / max(1.0 - sg, 0.001)
                    b = db / max(1.0 - sb, 0.001)
                case "burn":
                    r = 1.0 - (1.0 - dr) / max(sr, 0.001)
                    g = 1.0 - (1.0 - dg) / max(sg, 0.001)
                    b = 1.0 - (1.0 - db) / max(sb, 0.001)
                case "overlay":
                    r = dr < 0.5 ? 2 * dr * sr : 1 - 2 * (1 - dr) * (1 - sr)
                    g = dg < 0.5 ? 2 * dg * sg : 1 - 2 * (1 - dg) * (1 - sg)
                    b = db < 0.5 ? 2 * db * sb : 1 - 2 * (1 - db) * (1 - sb)
                default: // difference
                    r = abs(dr - sr)
                    g = abs(dg - sg)
                    b = abs(db - sb)
                }

                result.pixels[idx] = UInt8(max(0, min(255, Int(r * 255))))
                result.pixels[idx+1] = UInt8(max(0, min(255, Int(g * 255))))
                result.pixels[idx+2] = UInt8(max(0, min(255, Int(b * 255))))
                result.pixels[idx+3] = 255
            }
        }
        result.updatePixels()
        return result
    }

    func draw() {
        background(0)
        let hw = width / 2, hh = height / 2

        let dodge = blendImages("dodge")
        let burn = blendImages("burn")
        let overlay = blendImages("overlay")
        let diff = blendImages("difference")

        image(dodge, 0, 0)
        image(burn, hw, 0)
        image(overlay, 0, hh)
        image(diff, hw, hh)

        fill(255)
        textSize(12)
        text("Dodge", 5, 15)
        text("Burn", hw + 5, 15)
        text("Overlay", 5, hh + 15)
        text("Difference", hw + 5, hh + 15)
    }
}
