import metaphor

struct MParticle {
    var px: Float, py: Float
    var vx: Float, vy: Float
    var lifespan: Float = 255
    var isCrazy: Bool = false
    var theta: Float = 0
}

struct MParticleSystem {
    var origin: (Float, Float)
    var particles: [MParticle] = []
}

@main
final class MultipleParticleSystems: Sketch {
    var config: SketchConfig { SketchConfig(title: "Multiple Particle Systems", width: 640, height: 360) }

    var systems: [MParticleSystem] = []

    func draw() {
        background(0)
        for si in 0..<systems.count {
            let isCrazy = Int.random(in: 0...1) == 0
            systems[si].particles.append(MParticle(
                px: systems[si].origin.0, py: systems[si].origin.1,
                vx: random(-1, 1), vy: random(-2, 0), isCrazy: isCrazy
            ))
            var i = systems[si].particles.count - 1
            while i >= 0 {
                systems[si].particles[i].vx += 0
                systems[si].particles[i].vy += 0.05
                systems[si].particles[i].px += systems[si].particles[i].vx
                systems[si].particles[i].py += systems[si].particles[i].vy
                systems[si].particles[i].lifespan -= 2
                let life = systems[si].particles[i].lifespan
                stroke(255, life); fill(255, life)
                ellipse(systems[si].particles[i].px, systems[si].particles[i].py, 8, 8)
                if systems[si].particles[i].isCrazy {
                    let vel = systems[si].particles[i].vx
                    let spd = sqrt(systems[si].particles[i].vx * systems[si].particles[i].vx +
                                   systems[si].particles[i].vy * systems[si].particles[i].vy)
                    systems[si].particles[i].theta += (vel * spd) / 10
                    pushMatrix()
                    translate(systems[si].particles[i].px, systems[si].particles[i].py)
                    rotate(systems[si].particles[i].theta)
                    stroke(255, life)
                    line(0, 0, 25, 0)
                    popMatrix()
                }
                if life < 0 { systems[si].particles.remove(at: i) }
                i -= 1
            }
        }
        if systems.isEmpty {
            fill(255)
            textAlign(.center, .center)
            text("click mouse to add particle systems", width / 2, height / 2)
        }
    }

    func mousePressed() {
        systems.append(MParticleSystem(origin: (mouseX, mouseY)))
    }
}
