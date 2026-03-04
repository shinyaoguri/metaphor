import metaphor

struct Pelo {
    var z: Float
    var phi: Float
    var largo: Float
    var theta: Float

    init(radio: Float) {
        z = Float.random(in: -radio...radio)
        phi = Float.random(in: 0...Float.pi * 2)
        largo = Float.random(in: 1.15...1.2)
        theta = asin(z / radio)
    }
}

@main
final class Esfera: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1024, height: 768, title: "Esfera")
    }

    let cuantos = 16000
    var lista: [Pelo] = []
    var radio: Float = 200
    var rx: Float = 0
    var ry: Float = 0

    func setup() {
        radio = height / 3.5
        for _ in 0..<cuantos {
            lista.append(Pelo(radio: radio))
        }
    }

    func draw() {
        background(0)

        let rxp = (mouseX - width / 2) * 0.005
        let ryp = (mouseY - height / 2) * 0.005
        rx = rx * 0.9 + rxp * 0.1
        ry = ry * 0.9 + ryp * 0.1

        translate(width / 2, height / 2)
        rotateY(rx)
        rotateX(ry)
        fill(0)
        noStroke()
        sphere(radio)

        let time = Float(millis())
        for pelo in lista {
            let off = (noise(time * 0.0005, sin(pelo.phi)) - 0.5) * 0.3
            let offb = (noise(time * 0.0007, sin(pelo.z) * 0.01) - 0.5) * 0.3

            let thetaff = pelo.theta + off
            let phff = pelo.phi + offb
            let x = radio * cos(pelo.theta) * cos(pelo.phi)
            let y = radio * cos(pelo.theta) * sin(pelo.phi)
            let z = radio * sin(pelo.theta)

            let xo = radio * cos(thetaff) * cos(phff)
            let yo = radio * cos(thetaff) * sin(phff)
            let zo = radio * sin(thetaff)

            let xb = xo * pelo.largo
            let yb = yo * pelo.largo
            let zb = zo * pelo.largo

            stroke(200, 150)
            beginShape3D(.lines)
            vertex(x, y, z)
            vertex(xb, yb, zb)
            endShape3D()
        }
    }
}
