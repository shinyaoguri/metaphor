import metaphor

@main
final class AnimatedSprite: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "AnimatedSprite", width: 640, height: 360)
    }

    var animation1: [MImage] = []
    var animation2: [MImage] = []
    var frame1 = 0
    var frame2 = 0
    var xpos: Float = 0
    let drag: Float = 30.0
    var ypos: Float = 0
    let numFrames1 = 12
    let numFrames2 = 8
    let spriteSize = 80

    func setup() {
        frameRate(24)
        ypos = height * 0.25

        // Generate animation 1: shifting colored circles
        for i in 0..<numFrames1 {
            let img = createImage(spriteSize, spriteSize)
            img.loadPixels()
            let hue = Float(i) / Float(numFrames1)
            for y in 0..<spriteSize {
                for x in 0..<spriteSize {
                    let dx = Float(x) - Float(spriteSize) / 2
                    let dy = Float(y) - Float(spriteSize) / 2
                    let dist = sqrt(dx * dx + dy * dy)
                    let idx = (y * spriteSize + x) * 4
                    if dist < Float(spriteSize) / 2 {
                        let r = UInt8((sin(hue * .pi * 2) * 0.5 + 0.5) * 255)
                        let g = UInt8((sin(hue * .pi * 2 + 2.094) * 0.5 + 0.5) * 255)
                        let b = UInt8((sin(hue * .pi * 2 + 4.189) * 0.5 + 0.5) * 255)
                        let alpha = UInt8(255.0 * (1.0 - dist / (Float(spriteSize) / 2)))
                        img.pixels[idx] = r
                        img.pixels[idx + 1] = g
                        img.pixels[idx + 2] = b
                        img.pixels[idx + 3] = alpha
                    } else {
                        img.pixels[idx] = 0
                        img.pixels[idx + 1] = 0
                        img.pixels[idx + 2] = 0
                        img.pixels[idx + 3] = 0
                    }
                }
            }
            img.updatePixels()
            animation1.append(img)
        }

        // Generate animation 2: shifting colored squares
        for i in 0..<numFrames2 {
            let img = createImage(spriteSize, spriteSize)
            img.loadPixels()
            let phase = Float(i) / Float(numFrames2)
            for y in 0..<spriteSize {
                for x in 0..<spriteSize {
                    let idx = (y * spriteSize + x) * 4
                    let fx = Float(x) / Float(spriteSize)
                    let fy = Float(y) / Float(spriteSize)
                    let wave = sin((fx + phase) * .pi * 4) * sin((fy + phase) * .pi * 4)
                    let v = UInt8((wave * 0.5 + 0.5) * 255)
                    img.pixels[idx] = v
                    img.pixels[idx + 1] = UInt8(Float(v) * 0.6)
                    img.pixels[idx + 2] = 255
                    img.pixels[idx + 3] = 255
                }
            }
            img.updatePixels()
            animation2.append(img)
        }
    }

    func draw() {
        let dx = mouseX - xpos
        xpos = xpos + dx / drag

        if isMousePressed {
            background(153, 153, 0)
            frame1 = (frame1 + 1) % numFrames1
            image(animation1[frame1], xpos - Float(spriteSize) / 2, ypos)
        } else {
            background(255, 204, 0)
            frame2 = (frame2 + 1) % numFrames2
            image(animation2[frame2], xpos - Float(spriteSize) / 2, ypos)
        }
    }
}
