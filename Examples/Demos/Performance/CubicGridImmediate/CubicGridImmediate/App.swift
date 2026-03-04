import metaphor

@main
final class CubicGridImmediate: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "CubicGridImmediate", width: 640, height: 360)
    }

    let boxSize: Float = 20
    var margin: Float { boxSize * 2 }
    let depth: Float = 400

    var fcount = 0
    var lastm = 0
    var frate: Float = 0
    let fint = 3

    func setup() {
        frameRate(60)
        noStroke()
    }

    func draw() {
        background(255)

        pushMatrix()
        translate(width / 2, height / 2, -depth)
        rotateY(Float(frameCount) * 0.01)
        rotateX(Float(frameCount) * 0.01)

        var i = -depth / 2 + margin
        while i <= depth / 2 - margin {
            var j = -height + margin
            while j <= height - margin {
                var k = -width + margin
                while k <= width - margin {
                    fill(abs(i), abs(j), abs(k), 50)
                    pushMatrix()
                    translate(k, j, i)
                    box(boxSize)
                    popMatrix()
                    k += boxSize
                }
                j += boxSize
            }
            i += boxSize
        }
        popMatrix()

        fcount += 1
        let m = millis()
        if m - lastm > 1000 * fint {
            frate = Float(fcount) / Float(fint)
            fcount = 0
            lastm = m
        }
        fill(0)
        textSize(14)
        text("fps: \(Int(frate))", 10, 20)
    }
}
