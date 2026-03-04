import metaphor

struct Pelo {
    var zVal: Float
    var phi: Float
    var largo: Float
    var theta: Float

    init(radio: Float) {
        zVal = Float.random(in: -radio...radio)
        phi = Float.random(in: 0..<Float.pi * 2)
        largo = Float.random(in: 1.15...1.2)
        theta = asin(zVal / radio)
    }
}

@main
final class NoiseSphere: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "NoiseSphere", width: 640, height: 360)
    }

    let count = 4000
    var lista: [Pelo] = []
    var radio: Float = 0
    var rx: Float = 0
    var ry: Float = 0

    func setup() {
        radio = height / 3
        for _ in 0..<count {
            lista.append(Pelo(radio: radio))
        }
    }

    func draw() {
        background(0)
        translate(width / 2, height / 2)

        let rxp = (mouseX - width / 2) * 0.005
        let ryp = (mouseY - height / 2) * 0.005
        rx = rx * 0.9 + rxp * 0.1
        ry = ry * 0.9 + ryp * 0.1
        rotateY(rx)
        rotateX(ry)

        fill(0)
        noStroke()
        sphere(radio)

        let t = Float(millis()) * 0.0005
        let t2 = Float(millis()) * 0.0007

        for i in 0..<count {
            let p = lista[i]
            let off = (noise(t, sin(p.phi)) - 0.5) * 0.3
            let offb = (noise(t2, sin(p.zVal) * 0.01) - 0.5) * 0.3

            let thetaff = p.theta + off
            let phff = p.phi + offb

            let x = radio * cos(p.theta) * cos(p.phi)
            let y = radio * cos(p.theta) * sin(p.phi)
            let z = radio * sin(p.theta)

            let xo = radio * cos(thetaff) * cos(phff)
            let yo = radio * cos(thetaff) * sin(phff)
            let zo = radio * sin(thetaff)

            let xb = xo * p.largo
            let yb = yo * p.largo
            let zb = zo * p.largo

            stroke(200, 150)
            line(x, y, z, xb, yb, zb)
        }
    }
}
