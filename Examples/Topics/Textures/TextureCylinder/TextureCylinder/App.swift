import metaphor

@main
final class TextureCylinder: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "TextureCylinder")
    }

    let tubeRes = 32
    var tubeX: [Float] = []
    var tubeY: [Float] = []
    var img: MImage!

    func setup() {
        // Generate gradient texture
        let sz = 128
        img = createImage(sz, sz)
        img.loadPixels()
        for y in 0..<sz {
            for x in 0..<sz {
                let idx = (y * sz + x) * 4
                img.pixels[idx] = UInt8(x * 2 % 256)
                img.pixels[idx + 1] = UInt8(y * 2 % 256)
                img.pixels[idx + 2] = 150
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()

        let angle: Float = 270.0 / Float(tubeRes)
        for i in 0..<tubeRes {
            tubeX.append(cos(radians(Float(i) * angle)))
            tubeY.append(sin(radians(Float(i) * angle)))
        }
        noStroke()
    }

    func draw() {
        background(0)
        translate(width / 2, height / 2)
        rotateX(map(mouseY, 0, height, -.pi, .pi))
        rotateY(map(mouseX, 0, width, -.pi, .pi))

        // Cylinder tube
        beginShape(.triangleStrip)
        texture(img)
        for i in 0..<tubeRes {
            let x = tubeX[i] * 100
            let z = tubeY[i] * 100
            vertex(x, -100, z)
            vertex(x, 100, z)
        }
        endShape()

        // Side quad
        beginShape(.triangles)
        texture(img)
        vertex(0, -100, 0)
        vertex(100, -100, 0)
        vertex(100, 100, 0)
        vertex(0, -100, 0)
        vertex(100, 100, 0)
        vertex(0, 100, 0)
        endShape()
    }
}
