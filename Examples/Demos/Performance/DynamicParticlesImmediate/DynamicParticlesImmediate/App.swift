import metaphor

@main
final class DynamicParticlesImmediate: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "DynamicParticlesImmediate", width: 640, height: 480)
    }

    let npartTotal = 10000
    let npartPerFrame = 25
    let speed: Float = 1.0
    let gravity: Float = 0.05
    let partSize: Float = 6

    var partLifetime = 0
    var posX: [Float] = []
    var posY: [Float] = []
    var velX: [Float] = []
    var velY: [Float] = []
    var lifetimes: [Int] = []

    var fcount = 0
    var lastm = 0
    var frate: Float = 0
    let fint = 3

    func setup() {
        frameRate(120)
        partLifetime = npartTotal / npartPerFrame

        posX = Array(repeating: 0, count: npartTotal)
        posY = Array(repeating: 0, count: npartTotal)
        velX = Array(repeating: 0, count: npartTotal)
        velY = Array(repeating: 0, count: npartTotal)

        // Stagger lifetimes
        lifetimes = Array(repeating: 0, count: npartTotal)
        var t = -1
        for n in 0..<npartTotal {
            if n % npartPerFrame == 0 { t += 1 }
            lifetimes[n] = -t
        }
    }

    func draw() {
        background(0)
        noStroke()

        for n in 0..<npartTotal {
            lifetimes[n] += 1
            if lifetimes[n] == partLifetime {
                lifetimes[n] = 0
            }

            if lifetimes[n] >= 0 {
                let opacity = 1.0 - Float(lifetimes[n]) / Float(partLifetime)

                if lifetimes[n] == 0 {
                    posX[n] = mouseX
                    posY[n] = mouseY
                    let angle = Float.random(in: 0...TWO_PI)
                    let s = Float.random(in: 0.25...0.5) * speed
                    velX[n] = s * cos(angle)
                    velY[n] = s * sin(angle)
                } else {
                    posX[n] += velX[n]
                    posY[n] += velY[n]
                    velY[n] += gravity
                }

                fill(255, 255, 255, opacity * 255)
                ellipse(posX[n], posY[n], partSize, partSize)
            }
        }

        fcount += 1
        let m = millis()
        if m - lastm > 1000 * fint {
            frate = Float(fcount) / Float(fint)
            fcount = 0
            lastm = m
        }
        fill(255)
        textSize(16)
        text("fps: \(Int(frate))", 10, 20)
    }
}
