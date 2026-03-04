import metaphor

@main
final class RotatingArcs: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "RotatingArcs", width: 1024, height: 768)
    }

    let COUNT = 150
    var pt: [Float] = []        // rotx, roty, deg, rad, w, speed
    var styleColor: [(Float, Float, Float, Float)] = []  // RGBA colors
    var styleType: [Int] = []   // render style

    func setup() {
        background(255)

        for _ in 0..<COUNT {
            pt.append(Float.random(in: 0...TWO_PI))  // rotX
            pt.append(Float.random(in: 0...TWO_PI))  // rotY

            var deg = Float.random(in: 60...80)
            if Float.random(in: 0...100) > 90 {
                deg = Float(Int(Float.random(in: 8...27)) * 10)
            }
            pt.append(deg)

            pt.append(Float(Int(Float.random(in: 2...50)) * 5))  // radius

            var w = Float.random(in: 4...32)
            if Float.random(in: 0...100) > 90 {
                w = Float.random(in: 40...60)
            }
            pt.append(w)

            pt.append(radians(Float.random(in: 5...30)) / 5)  // speed

            // Color
            let prob = Float.random(in: 0...100)
            let fract = Float.random(in: 0...1)
            var r: Float, g: Float, b: Float
            if prob < 50 {
                r = 200 + (50 - 200) * fract
                g = 255 + (120 - 255) * fract
                b = 0 + (0 - 0) * fract
            } else if prob < 90 {
                r = 255 + (255 - 255) * fract
                g = 100 + (255 - 100) * fract
                b = 0 + (0 - 0) * fract
            } else {
                r = 255; g = 255; b = 255
            }
            styleColor.append((r, g, b, 210))
            styleType.append(Int.random(in: 0...2))
        }
    }

    func draw() {
        background(0)
        translate(width / 2, height / 2, 0)
        rotateX(.pi / 6)
        rotateY(.pi / 6)

        var index = 0
        for i in 0..<COUNT {
            pushMatrix()
            rotateX(pt[index]); index += 1
            rotateY(pt[index]); index += 1

            let deg = pt[index]; index += 1
            let rad = pt[index]; index += 1
            let w = pt[index]; index += 1
            let spd = pt[index]; index += 1

            let c = styleColor[i]

            if styleType[i] == 0 {
                stroke(c.0, c.1, c.2, c.3)
                noFill()
                strokeWeight(1)
                drawArcLine(0, 0, deg, rad, w)
            } else if styleType[i] == 1 {
                fill(c.0, c.1, c.2, c.3)
                noStroke()
                drawArcLineBars(0, 0, deg, rad, w)
            } else {
                fill(c.0, c.1, c.2, c.3)
                noStroke()
                drawArc(0, 0, deg, rad, w)
            }

            // Increase rotation
            pt[index - 6] += spd / 10
            pt[index - 5] += spd / 20

            popMatrix()
        }
    }

    func drawArcLine(_ x: Float, _ y: Float, _ degrees: Float, _ radius: Float, _ w: Float) {
        let lineCount = Int(w / 2)
        var r = radius
        for _ in 0..<lineCount {
            beginShape()
            for i in 0..<Int(degrees) {
                let angle = radians(Float(i))
                vertex(x + cos(angle) * r, y + sin(angle) * r)
            }
            endShape()
            r += 2
        }
    }

    func drawArcLineBars(_ x: Float, _ y: Float, _ degrees: Float, _ radius: Float, _ w: Float) {
        // QUADS → 2 triangles each
        beginShape(.triangles)
        var i: Float = 0
        while i < degrees / 4 {
            let angle1 = radians(i)
            let angle2 = radians(i + 2)
            let ax = x + cos(angle1) * radius
            let ay = y + sin(angle1) * radius
            let bx = x + cos(angle1) * (radius + w)
            let by = y + sin(angle1) * (radius + w)
            let cx = x + cos(angle2) * (radius + w)
            let cy = y + sin(angle2) * (radius + w)
            let dx = x + cos(angle2) * radius
            let dy = y + sin(angle2) * radius
            // Triangle 1
            vertex(ax, ay); vertex(bx, by); vertex(cx, cy)
            // Triangle 2
            vertex(ax, ay); vertex(cx, cy); vertex(dx, dy)
            i += 4
        }
        endShape()
    }

    func drawArc(_ x: Float, _ y: Float, _ degrees: Float, _ radius: Float, _ w: Float) {
        beginShape(.triangleStrip)
        for i in 0..<Int(degrees) {
            let angle = radians(Float(i))
            vertex(x + cos(angle) * radius, y + sin(angle) * radius)
            vertex(x + cos(angle) * (radius + w), y + sin(angle) * (radius + w))
        }
        endShape()
    }
}
