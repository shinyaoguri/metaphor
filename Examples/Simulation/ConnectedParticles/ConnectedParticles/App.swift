import metaphor

struct Particle {
    var x: Float
    var y: Float
    var vx: Float
    var vy: Float
    var radius: Float
}

@main
final class ConnectedParticlesExample: Sketch {
    var particles: [Particle] = []
    let connectionDist: Float = 150

    var config: SketchConfig {
        SketchConfig(title: "Connected Particles")
    }

    func setup() {
        for _ in 0..<80 {
            particles.append(Particle(
                x: Float.random(in: 0...1920),
                y: Float.random(in: 0...1080),
                vx: Float.random(in: -0.8...0.8),
                vy: Float.random(in: -0.8...0.8),
                radius: Float.random(in: 2...4)
            ))
        }
    }

    func draw() {
        background(Color(r: 0.05, g: 0.05, b: 0.1))

        let w = width
        let h = height

        for i in 0..<particles.count {
            if input.isMouseDown {
                let dx = input.mouseX - particles[i].x
                let dy = input.mouseY - particles[i].y
                let dist = sqrt(dx * dx + dy * dy)
                if dist > 1 {
                    particles[i].vx += (dx / dist) * 0.05
                    particles[i].vy += (dy / dist) * 0.05
                }
            }

            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            particles[i].vx *= 0.999
            particles[i].vy *= 0.999

            if particles[i].x < 0 { particles[i].x = 0; particles[i].vx *= -1 }
            if particles[i].x > w { particles[i].x = w; particles[i].vx *= -1 }
            if particles[i].y < 0 { particles[i].y = 0; particles[i].vy *= -1 }
            if particles[i].y > h { particles[i].y = h; particles[i].vy *= -1 }
        }

        // 接続線
        strokeWeight(1)
        for i in 0..<particles.count {
            for j in (i + 1)..<particles.count {
                let dx = particles[i].x - particles[j].x
                let dy = particles[i].y - particles[j].y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < connectionDist {
                    let alpha = (1.0 - dist / connectionDist) * 0.6
                    stroke(Color(r: 0.4, g: 0.6, b: 1.0, a: alpha))
                    line(particles[i].x, particles[i].y,
                         particles[j].x, particles[j].y)
                }
            }
        }

        // パーティクル
        noStroke()
        for p in particles {
            fill(Color(r: 0.6, g: 0.8, b: 1.0, a: 0.9))
            circle(p.x, p.y, p.radius * 2)
        }
    }
}
