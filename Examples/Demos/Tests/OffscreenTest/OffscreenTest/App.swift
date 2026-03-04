import metaphor

@main
final class OffscreenTest: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "OffscreenTest", width: 400, height: 400)
    }

    var offscreen: MImage!

    func setup() {
        offscreen = createImage(400, 400)
    }

    func draw() {
        background(0)

        // Draw to offscreen image (simulating PGraphics)
        offscreen.loadPixels()
        // Fill with red background
        for i in stride(from: 0, to: offscreen.pixels.count, by: 4) {
            offscreen.pixels[i] = 255     // R
            offscreen.pixels[i + 1] = 0   // G
            offscreen.pixels[i + 2] = 0   // B
            offscreen.pixels[i + 3] = 255 // A
        }
        // Draw a white circle at mouse position
        let cx = Int(mouseX)
        let cy = Int(mouseY)
        let r = 50
        for y in max(0, cy - r)..<min(400, cy + r) {
            for x in max(0, cx - r)..<min(400, cx + r) {
                let dx = x - cx
                let dy = y - cy
                if dx * dx + dy * dy <= r * r {
                    let idx = (y * 400 + x) * 4
                    offscreen.pixels[idx] = 255
                    offscreen.pixels[idx + 1] = 255
                    offscreen.pixels[idx + 2] = 255
                    offscreen.pixels[idx + 3] = 255
                }
            }
        }
        offscreen.updatePixels()

        image(offscreen, 0, 0, 400, 400)
    }
}
