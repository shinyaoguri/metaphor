import metaphor

@main
final class RGBCube: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "RGBCube", width: 640, height: 360)
    }

    var xmag: Float = 0
    var ymag: Float = 0

    func setup() {
        noStroke()
    }

    func draw() {
        background(128)

        pushMatrix()
        translate(width / 2, height / 2, -30)

        let newXmag = mouseX / width * Float.pi * 2
        let newYmag = mouseY / height * Float.pi * 2

        let diffX = xmag - newXmag
        if abs(diffX) > 0.01 { xmag -= diffX / 4.0 }
        let diffY = ymag - newYmag
        if abs(diffY) > 0.01 { ymag -= diffY / 4.0 }

        rotateX(-ymag)
        rotateY(-xmag)
        scale(90)

        // Front face (+Z): cyan->white->magenta->blue
        fill(128, 128, 255)
        beginShape(.triangles)
        vertex(-1, 1, 1); vertex(1, 1, 1); vertex(1, -1, 1)
        vertex(-1, 1, 1); vertex(1, -1, 1); vertex(-1, -1, 1)
        endShape()

        // Right face (+X): white->yellow->red->magenta
        fill(255, 128, 128)
        beginShape(.triangles)
        vertex(1, 1, 1); vertex(1, 1, -1); vertex(1, -1, -1)
        vertex(1, 1, 1); vertex(1, -1, -1); vertex(1, -1, 1)
        endShape()

        // Back face (-Z): yellow->green->black->red
        fill(128, 128, 0)
        beginShape(.triangles)
        vertex(1, 1, -1); vertex(-1, 1, -1); vertex(-1, -1, -1)
        vertex(1, 1, -1); vertex(-1, -1, -1); vertex(1, -1, -1)
        endShape()

        // Left face (-X): green->cyan->blue->black
        fill(0, 128, 128)
        beginShape(.triangles)
        vertex(-1, 1, -1); vertex(-1, 1, 1); vertex(-1, -1, 1)
        vertex(-1, 1, -1); vertex(-1, -1, 1); vertex(-1, -1, -1)
        endShape()

        // Top face (-Y): green->yellow->white->cyan
        fill(128, 255, 128)
        beginShape(.triangles)
        vertex(-1, 1, -1); vertex(1, 1, -1); vertex(1, 1, 1)
        vertex(-1, 1, -1); vertex(1, 1, 1); vertex(-1, 1, 1)
        endShape()

        // Bottom face (+Y): black->red->magenta->blue
        fill(128, 0, 128)
        beginShape(.triangles)
        vertex(-1, -1, -1); vertex(1, -1, -1); vertex(1, -1, 1)
        vertex(-1, -1, -1); vertex(1, -1, 1); vertex(-1, -1, 1)
        endShape()

        popMatrix()
    }
}
