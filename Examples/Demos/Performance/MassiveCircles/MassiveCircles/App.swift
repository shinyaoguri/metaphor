import metaphor

@main
final class MassiveCircles: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 960, height: 540, title: "Massive Circles")
    }

    let dotCount = 100_000
    var dots: [CircleInstance] = []
    var velocities: [SIMD2<Float>] = []

    func setup() {
        frameRate(120)
        noStroke()
        dots.reserveCapacity(dotCount)
        velocities.reserveCapacity(dotCount)

        for i in 0..<dotCount {
            let x = Float.random(in: 0...width)
            let y = Float.random(in: 0...height)
            let speed = Float.random(in: 0.25...1.4)
            let angle = Float.random(in: 0...TWO_PI)
            let diameter = Float.random(in: 1.5...4.5)
            let hue = Float(i % 360) / 360.0
            dots.append(CircleInstance(
                x: x,
                y: y,
                diameter: diameter,
                color: Color(hue: hue, saturation: 0.75, brightness: 1.0, alpha: 0.55)
            ))
            velocities.append(SIMD2(cos(angle) * speed, sin(angle) * speed))
        }
    }

    func draw() {
        background(0)

        for i in dots.indices {
            var p = dots[i].position + velocities[i]
            var v = velocities[i]
            if p.x < 0 || p.x > width {
                v.x = -v.x
                p.x = min(max(p.x, 0), width)
            }
            if p.y < 0 || p.y > height {
                v.y = -v.y
                p.y = min(max(p.y, 0), height)
            }
            dots[i].position = p
            velocities[i] = v
        }

        blendMode(.additive)
        circles(dots)

        blendMode(.alpha)
        fill(255)
        textSize(14)
        text("circles: \(dots.count)", 14, 24)
    }
}
