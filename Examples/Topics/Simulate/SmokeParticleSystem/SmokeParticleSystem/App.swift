import metaphor

struct SmkParticle {
    var px: Float, py: Float
    var vx: Float, vy: Float
    var ax: Float = 0, ay: Float = 0
    var lifespan: Float = 100
}

@main
final class SmokeParticleSystem: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Smoke Particle System") }

    var particles: [SmkParticle] = []
    var originX: Float = 0, originY: Float = 0

    func setup() {
        originX = width / 2
        originY = height - 60
    }

    func draw() {
        background(0)
        let windX = map(mouseX, 0, width, -0.2, 0.2)
        for i in 0..<particles.count {
            particles[i].ax += windX; particles[i].ay += 0
        }
        for _ in 0..<2 {
            particles.append(SmkParticle(
                px: originX, py: originY,
                vx: randomGaussian() * 0.3, vy: randomGaussian() * 0.3 - 1
            ))
        }
        var i = particles.count - 1
        while i >= 0 {
            particles[i].vx += particles[i].ax
            particles[i].vy += particles[i].ay
            particles[i].px += particles[i].vx
            particles[i].py += particles[i].vy
            particles[i].lifespan -= 2.5
            particles[i].ax = 0; particles[i].ay = 0
            noStroke()
            fill(255, particles[i].lifespan * 2.55)
            ellipse(particles[i].px, particles[i].py, 24, 24)
            if particles[i].lifespan <= 0 { particles.remove(at: i) }
            i -= 1
        }
        // Wind arrow
        pushMatrix()
        translate(width / 2, 50)
        rotate(atan2(0, windX))
        let len = abs(windX) * 500
        stroke(255)
        line(0, 0, len, 0)
        line(len, 0, len - 4, 2)
        line(len, 0, len - 4, -2)
        popMatrix()
    }
}
