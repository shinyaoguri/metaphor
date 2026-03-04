import metaphor

@main
final class Vertices: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Vertices", width: 640, height: 360)
    }

    func setup() {}

    func draw() {
        background(0)
        lights()
        translate(width / 2, height / 2)
        rotateY(map(mouseX, 0, width, 0, .pi))
        rotateZ(map(mouseY, 0, height, 0, -.pi))
        noStroke()
        fill(255, 255, 255)
        translate(0, -40, 0)
        drawCylinder(10, 180, 200, 16)
    }

    func drawCylinder(_ topRadius: Float, _ bottomRadius: Float, _ tall: Float, _ sides: Int) {
        let angleIncrement = Float.pi * 2 / Float(sides)

        // Tube
        beginShape(.triangleStrip)
        var angle: Float = 0
        for _ in 0...sides {
            vertex(topRadius * cos(angle), 0, topRadius * sin(angle))
            vertex(bottomRadius * cos(angle), tall, bottomRadius * sin(angle))
            angle += angleIncrement
        }
        endShape()

        // Top cap
        if topRadius != 0 {
            beginShape(.triangleFan)
            vertex(0, 0, 0)
            angle = 0
            for _ in 0...sides {
                vertex(topRadius * cos(angle), 0, topRadius * sin(angle))
                angle += angleIncrement
            }
            endShape()
        }

        // Bottom cap
        if bottomRadius != 0 {
            beginShape(.triangleFan)
            vertex(0, tall, 0)
            angle = 0
            for _ in 0...sides {
                vertex(bottomRadius * cos(angle), tall, bottomRadius * sin(angle))
                angle += angleIncrement
            }
            endShape()
        }
    }
}
