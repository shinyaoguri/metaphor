import metaphor

@main
final class Sequential: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Sequential")
    }

    let numFrames = 12
    var images: [MImage] = []
    var currentFrame = 0
    let frameW = 120
    let frameH = 120

    func setup() {
        frameRate(24)

        // Generate 12 frames with rotating line patterns
        for i in 0..<numFrames {
            guard let img = createImage(frameW, frameH) else { return }
            img.loadPixels()
            let angle = Float(i) / Float(numFrames) * .pi * 2
            let cx = Float(frameW) / 2
            let cy = Float(frameH) / 2
            // Fill with dark background
            for p in 0..<(frameW * frameH) {
                let idx = p * 4
                img.pixels[idx] = 20
                img.pixels[idx + 1] = 20
                img.pixels[idx + 2] = 40
                img.pixels[idx + 3] = 255
            }
            // Draw a bright dot that orbits
            let dotX = Int(cx + cos(angle) * 40)
            let dotY = Int(cy + sin(angle) * 40)
            for dy in -8...8 {
                for dx in -8...8 {
                    if dx * dx + dy * dy <= 64 {
                        let px = dotX + dx
                        let py = dotY + dy
                        if px >= 0 && px < frameW && py >= 0 && py < frameH {
                            let idx = (py * frameW + px) * 4
                            let hue = Float(i) / Float(numFrames)
                            img.pixels[idx] = UInt8((sin(hue * .pi * 2) * 0.5 + 0.5) * 255)
                            img.pixels[idx + 1] = UInt8((sin(hue * .pi * 2 + 2.094) * 0.5 + 0.5) * 255)
                            img.pixels[idx + 2] = UInt8((sin(hue * .pi * 2 + 4.189) * 0.5 + 0.5) * 255)
                            img.pixels[idx + 3] = 255
                        }
                    }
                }
            }
            img.updatePixels()
            images.append(img)
        }
    }

    func draw() {
        background(0)
        currentFrame = (currentFrame + 1) % numFrames
        var offset = 0
        var x: Float = -100
        while x < width {
            image(images[(currentFrame + offset) % numFrames], x, -20)
            offset += 2
            image(images[(currentFrame + offset) % numFrames], x, height / 2)
            offset += 2
            x += Float(images[0].width)
        }
    }
}
