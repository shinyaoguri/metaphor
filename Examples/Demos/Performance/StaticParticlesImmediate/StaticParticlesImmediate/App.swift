import metaphor

@main
final class StaticParticlesImmediate: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "StaticParticlesImmediate")
    }

    let npartTotal = 5000
    let partSize: Float = 6
    var posX: [Float] = []
    var posY: [Float] = []
    var posZ: [Float] = []

    var fcount = 0
    var lastm = 0
    var frate: Float = 0
    let fint = 3

    func setup() {
        frameRate(60)
        for _ in 0..<npartTotal {
            posX.append(Float.random(in: -500...500))
            posY.append(Float.random(in: -500...500))
            posZ.append(Float.random(in: -500...500))
        }
    }

    func draw() {
        background(0)
        noStroke()

        translate(width / 2, height / 2)
        rotateY(Float(frameCount) * 0.01)

        fill(255, 200)
        for n in 0..<npartTotal {
            pushMatrix()
            translate(posX[n], posY[n], posZ[n])
            ellipse(0, 0, partSize, partSize)
            popMatrix()
        }

        fcount += 1
        let m = millis()
        if m - lastm > 1000 * fint {
            frate = Float(fcount) / Float(fint)
            fcount = 0
            lastm = m
        }
        fill(255)
        textSize(14)
        text("fps: \(Int(frate))", 10, 20)
    }
}
