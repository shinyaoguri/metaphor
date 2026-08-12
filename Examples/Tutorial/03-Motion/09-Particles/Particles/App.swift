import metaphor

/// 粒 1 つぶんの状態。`life` が寿命で、1 から 0 へ減っていく。
struct Particle {
    var position: Vec2
    var velocity: Vec2
    var life: Float
    var size: Float

    mutating func update() {
        // 力を加える = 加速度を速度に足す。ここでは下向きの重力だけ
        velocity += Vec2(0, 0.07)
        position += velocity
        life -= 0.012
    }
}

@main
final class Particles: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Particles")
    }

    var particles: [Particle] = []

    func setup() {
        randomSeed(21)
        noStroke()
    }

    func draw() {
        background(18)

        // 1. 生む。毎フレーム決まった数だけ足す
        for _ in 0..<3 {
            particles.append(spawn())
        }

        // 2. 動かす
        for i in particles.indices {
            particles[i].update()
        }

        // 3. 消す。寿命が尽きたものを配列から取り除かないと、増え続ける
        particles.removeAll { $0.life <= 0 }

        // 加算合成にすると、重なったところが明るくなって炎のように見える
        blendMode(.additive)
        for particle in particles {
            // 残り寿命をそのまま不透明度と大きさに使うと、消えぎわが自然になる
            fill(255, 170, 90, particle.life * 190)
            circle(particle.position.x, particle.position.y, particle.size * particle.life)
        }
        blendMode(.alpha)

        fill(190)
        textSize(13)
        text("particles = \(particles.count)", 20, 28)
    }

    /// 画面の下から、上向きに少しばらつかせて 1 つ生む。
    private func spawn() -> Particle {
        let angle = -HALF_PI + random(-0.32, 0.32)
        let speed = random(2.4, 4.8)
        return Particle(
            position: Vec2(width * 0.5, height - 24),
            velocity: Vec2(cos(angle), sin(angle)) * speed,
            life: 1,
            size: random(10, 26)
        )
    }
}
