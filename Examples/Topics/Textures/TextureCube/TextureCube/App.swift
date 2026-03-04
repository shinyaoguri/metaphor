import metaphor

@main
final class TextureCube: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "TextureCube")
    }

    var tex: MImage!
    var rotx: Float = .pi / 4
    var roty: Float = .pi / 4

    func setup() {
        // Generate checkerboard texture
        let sz = 64
        tex = createImage(sz, sz)
        tex.loadPixels()
        for y in 0..<sz {
            for x in 0..<sz {
                let idx = (y * sz + x) * 4
                let isWhite = ((x / 8) + (y / 8)) % 2 == 0
                let v: UInt8 = isWhite ? 255 : 100
                tex.pixels[idx] = v
                tex.pixels[idx + 1] = v
                tex.pixels[idx + 2] = v
                tex.pixels[idx + 3] = 255
            }
        }
        tex.updatePixels()

        fill(255)
        stroke(44, 48, 32)
    }

    func draw() {
        background(0)
        noStroke()
        translate(width / 2, height / 2, -100)
        rotateX(rotx)
        rotateY(roty)
        scale(90)
        texturedCube()
    }

    func texturedCube() {
        beginShape(.triangles)
        texture(tex)

        // +Z front face (2 triangles per quad)
        vertex(-1, -1, 1); vertex(1, -1, 1); vertex(1, 1, 1)
        vertex(-1, -1, 1); vertex(1, 1, 1); vertex(-1, 1, 1)

        // -Z back face
        vertex(1, -1, -1); vertex(-1, -1, -1); vertex(-1, 1, -1)
        vertex(1, -1, -1); vertex(-1, 1, -1); vertex(1, 1, -1)

        // +Y bottom face
        vertex(-1, 1, 1); vertex(1, 1, 1); vertex(1, 1, -1)
        vertex(-1, 1, 1); vertex(1, 1, -1); vertex(-1, 1, -1)

        // -Y top face
        vertex(-1, -1, -1); vertex(1, -1, -1); vertex(1, -1, 1)
        vertex(-1, -1, -1); vertex(1, -1, 1); vertex(-1, -1, 1)

        // +X right face
        vertex(1, -1, 1); vertex(1, -1, -1); vertex(1, 1, -1)
        vertex(1, -1, 1); vertex(1, 1, -1); vertex(1, 1, 1)

        // -X left face
        vertex(-1, -1, -1); vertex(-1, -1, 1); vertex(-1, 1, 1)
        vertex(-1, -1, -1); vertex(-1, 1, 1); vertex(-1, 1, -1)

        endShape()
    }

    func mouseDragged() {
        let rate: Float = 0.01
        rotx += (pmouseY - mouseY) * rate
        roty += (mouseX - pmouseX) * rate
    }
}
