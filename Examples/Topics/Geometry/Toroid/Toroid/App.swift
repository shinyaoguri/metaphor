import metaphor

@main
final class Toroid: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Toroid", width: 640, height: 360)
    }

    var pts = 40
    var radius: Float = 60.0
    var segments = 60
    var latheRadius: Float = 100.0
    var isWireFrame = false
    var isHelix = false
    let helixOffset: Float = 5.0

    func setup() {}

    func draw() {
        background(50, 64, 42)
        lights()

        if isWireFrame {
            stroke(255, 255, 150)
            noFill()
        } else {
            noStroke()
            fill(150, 195, 125)
        }

        translate(width / 2, height / 2, -100)
        rotateX(Float(frameCount) * .pi / 150)
        rotateY(Float(frameCount) * .pi / 170)
        rotateZ(Float(frameCount) * .pi / 90)

        // Build cross-section vertices
        var verts = [(x: Float, z: Float)](repeating: (0, 0), count: pts + 1)
        var angle: Float = 0
        for i in 0...pts {
            verts[i].x = latheRadius + sin(radians(angle)) * radius
            if isHelix {
                verts[i].z = cos(radians(angle)) * radius - (helixOffset * Float(segments)) / 2
            } else {
                verts[i].z = cos(radians(angle)) * radius
            }
            angle += 360.0 / Float(pts)
        }

        // Draw toroid by lathing
        var prevRing = [(x: Float, y: Float, z: Float)](repeating: (0, 0, 0), count: pts + 1)
        var latheAngle: Float = 0

        for i in 0...segments {
            var currentRing = [(x: Float, y: Float, z: Float)](repeating: (0, 0, 0), count: pts + 1)

            beginShape(.triangleStrip)
            for j in 0...pts {
                if i > 0 {
                    vertex(prevRing[j].x, prevRing[j].y, prevRing[j].z)
                }

                let cx = cos(radians(latheAngle)) * verts[j].x
                let cy = sin(radians(latheAngle)) * verts[j].x
                var cz = verts[j].z
                if isHelix {
                    verts[j].z += helixOffset
                    cz = verts[j].z
                }

                currentRing[j] = (cx, cy, cz)
                vertex(cx, cy, cz)
            }
            endShape()

            prevRing = currentRing
            if isHelix {
                latheAngle += 720.0 / Float(segments)
            } else {
                latheAngle += 360.0 / Float(segments)
            }
        }
    }

    func keyPressed() {
        if keyCode == .upArrow && pts < 40 { pts += 1 }
        if keyCode == .downArrow && pts > 3 { pts -= 1 }
        if keyCode == .leftArrow && segments > 3 { segments -= 1 }
        if keyCode == .rightArrow && segments < 80 { segments += 1 }
        if key == "a" && latheRadius > 0 { latheRadius -= 1 }
        if key == "s" { latheRadius += 1 }
        if key == "z" && radius > 10 { radius -= 1 }
        if key == "x" { radius += 1 }
        if key == "w" { isWireFrame = !isWireFrame }
        if key == "h" { isHelix = !isHelix }
    }
}
