import metaphor

struct Particle {
    var x: Float
    var y: Float
    var vx: Float
    var vy: Float
    var life: Float
    var hue: Float
    var size: Float
}

@main
final class ParticlesExample: Sketch {
    var particles: [Particle] = []
    let maxParticles = 2000

    var config: SketchConfig {
        SketchConfig(title: "Particles", syphonName: "Particles")
    }

    func setup() {
        for _ in 0..<maxParticles {
            var p = spawnParticle()
            p.x = Float.random(in: 0...1920)
            p.y = Float.random(in: 0...1080)
            p.life = Float.random(in: 0...1)
            particles.append(p)
        }
    }

    private func spawnParticle() -> Particle {
        let angle = Float.random(in: 0...(2 * .pi))
        let speed = Float.random(in: 50...250)
        return Particle(
            x: 960, y: 540,
            vx: cos(angle) * speed,
            vy: sin(angle) * speed,
            life: Float.random(in: 0.5...1.0),
            hue: angle / (2 * Float.pi),
            size: Float.random(in: 2...6)
        )
    }

    func draw() {
        background(Color(gray: 0.0, alpha: 0.08))
        noStroke()

        let cx = width / 2
        let cy = height / 2
        let dt = max(deltaTime, 0.001)

        for i in 0..<particles.count {
            particles[i].life -= dt * 0.3

            if particles[i].life <= 0 {
                particles[i] = spawnParticle()
                particles[i].x = cx
                particles[i].y = cy
                continue
            }

            // 中心への引力 + 渦巻き効果
            let dx = cx - particles[i].x
            let dy = cy - particles[i].y
            let dist = sqrt(dx * dx + dy * dy)
            if dist > 1 {
                let nx = dx / dist
                let ny = dy / dist
                let force = dt * 60
                particles[i].vx += (nx * 3 + (-ny) * 6) * force
                particles[i].vy += (ny * 3 + nx * 6) * force
            }

            // 減衰
            particles[i].vx *= 0.995
            particles[i].vy *= 0.995

            // 位置更新
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt

            // 描画
            let alpha = particles[i].life
            fill(Color(hue: particles[i].hue, saturation: 0.8, brightness: 1.0, alpha: alpha))
            circle(particles[i].x, particles[i].y, particles[i].size)
        }
    }
}
