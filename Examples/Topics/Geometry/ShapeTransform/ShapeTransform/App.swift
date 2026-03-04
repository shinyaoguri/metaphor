import metaphor

@main
final class ShapeTransform: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ShapeTransform")
    }

    var pts = 4
    var radius: Float = 99
    var cylinderLength: Float = 95
    var isPyramid = false
    let angleInc: Float = .pi / 300.0

    func setup() {
        noStroke()
    }

    func draw() {
        background(170, 95, 95)
        lights()
        fill(255, 200, 200)
        translate(width / 2, height / 2)
        rotateX(Float(frameCount) * angleInc)
        rotateY(Float(frameCount) * angleInc)
        rotateZ(Float(frameCount) * angleInc)

        // Build vertices for top and bottom rings
        var topVerts: [(Float, Float, Float)] = []
        var bottomVerts: [(Float, Float, Float)] = []

        var cLen = cylinderLength
        for ring in 0..<2 {
            var angle: Float = 0
            for _ in 0...pts {
                let x: Float
                let y: Float
                if isPyramid && ring == 1 {
                    x = 0; y = 0
                } else {
                    x = cos(radians(angle)) * radius
                    y = sin(radians(angle)) * radius
                }
                if ring == 0 {
                    topVerts.append((x, y, cLen))
                } else {
                    bottomVerts.append((x, y, -cLen))
                }
                angle += 360.0 / Float(pts)
            }
            cLen *= -1
        }

        // Draw tube
        beginShape(.triangleStrip)
        for j in 0...pts {
            vertex(topVerts[j].0, topVerts[j].1, topVerts[j].2)
            vertex(bottomVerts[j].0, bottomVerts[j].1, bottomVerts[j].2)
        }
        endShape()

        // Draw caps
        beginShape(.triangleFan)
        vertex(0, 0, cylinderLength)
        for j in 0...pts {
            vertex(topVerts[j].0, topVerts[j].1, topVerts[j].2)
        }
        endShape()

        beginShape(.triangleFan)
        vertex(0, 0, -cylinderLength)
        for j in 0...pts {
            vertex(bottomVerts[j].0, bottomVerts[j].1, bottomVerts[j].2)
        }
        endShape()
    }

    func keyPressed() {
        if keyCode == 126 && pts < 90 { pts += 1 }  // up arrow
        if keyCode == 125 && pts > 4 { pts -= 1 }   // down arrow
        if key == "p" { isPyramid = !isPyramid }
    }
}
