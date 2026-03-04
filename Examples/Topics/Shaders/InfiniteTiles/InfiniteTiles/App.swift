import metaphor

// NOTE: Original uses a GLSL scroller shader with texture repeat.
// This version creates a scrolling tiled pattern using CPU rendering.

@main
final class InfiniteTiles: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "InfiniteTiles", width: 640, height: 480)
    }

    var tileImg: MImage!
    var displayImg: MImage!
    let tileSize = 64

    func setup() {
        noStroke()

        // Generate a Penrose-like tile pattern
        tileImg = createImage(tileSize, tileSize)
        tileImg.loadPixels()
        for y in 0..<tileSize {
            for x in 0..<tileSize {
                let idx = (y * tileSize + x) * 4
                let nx = Float(x) / Float(tileSize)
                let ny = Float(y) / Float(tileSize)
                let v = sin(nx * .pi * 4) * cos(ny * .pi * 4) * 0.5 + 0.5
                let edge = (x == 0 || y == 0) ? 0.3 : 1.0
                let r = UInt8(max(0, min(255, Int(v * 180 * Float(edge) + 40))))
                let g = UInt8(max(0, min(255, Int(v * 120 * Float(edge) + 60))))
                let b = UInt8(max(0, min(255, Int(v * 80 * Float(edge) + 80))))
                tileImg.pixels[idx] = r
                tileImg.pixels[idx + 1] = g
                tileImg.pixels[idx + 2] = b
                tileImg.pixels[idx + 3] = 255
            }
        }
        tileImg.updatePixels()

        displayImg = createImage(Int(width), Int(height))
    }

    func draw() {
        let w = Int(width), h = Int(height)
        let t = Float(millis()) / 1000.0
        let scrollX = Int(t * 50) % tileSize
        let scrollY = Int(t * 30) % tileSize

        tileImg.loadPixels()
        displayImg.loadPixels()

        for y in 0..<h {
            for x in 0..<w {
                let tx = (x + scrollX) % tileSize
                let ty = (y + scrollY) % tileSize
                let srcIdx = (ty * tileSize + tx) * 4
                let dstIdx = (y * w + x) * 4
                displayImg.pixels[dstIdx] = tileImg.pixels[srcIdx]
                displayImg.pixels[dstIdx + 1] = tileImg.pixels[srcIdx + 1]
                displayImg.pixels[dstIdx + 2] = tileImg.pixels[srcIdx + 2]
                displayImg.pixels[dstIdx + 3] = 255
            }
        }
        displayImg.updatePixels()
        image(displayImg, 0, 0)
    }
}
