import metaphor

struct SParticle {
    var px: Float, py: Float
    var vx: Float, vy: Float
    var ax: Float = 0, ay: Float = 0.05
    var lifespan: Float = 255
}

@main
final class SimpleParticleSystem: Sketch {
    var config: SketchConfig { SketchConfig(title: "Simple Particle System", width: 640, height: 360) }

    var particles: [SParticle] = []
    var originX: Float = 0, originY: Float = 50

    func setup() {
        originX = width / 2
    }

    func draw() {
        background(0)
        particles.append(SParticle(
            px: originX, py: originY,
            vx: random(-1, 1), vy: random(-2, 0)
        ))
        var i = particles.count - 1
        while i >= 0 {
            particles[i].vx += particles[i].ax
            particles[i].vy += particles[i].ay
            particles[i].px += particles[i].vx
            particles[i].py += particles[i].vy
            particles[i].lifespan -= 1
            stroke(255, particles[i].lifespan)
            fill(255, particles[i].lifespan)
            ellipse(particles[i].px, particles[i].py, 8, 8)
            if particles[i].lifespan < 0 { particles.remove(at: i) }
            i -= 1
        }
    }
}
