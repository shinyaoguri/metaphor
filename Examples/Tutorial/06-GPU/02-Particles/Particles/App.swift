import metaphor

@main
final class Particles: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Particles")
    }

    let count = 1_000_000
    var system: ParticleSystem?

    func setup() {
        guard let ps = try? createParticleSystem(count: count) else { return }

        // 位置はワールド座標 = ピクセル座標。y は下向き
        ps.setEmitter(.circle(x: 320, y: 290, z: 0, radius: 70))
        ps.particleLife = 3.0
        ps.particleSize = 1.5
        ps.emissionRate = Float(count) / ps.particleLife   // 常に埋まる量を出し続ける
        // 加算合成なので 1 粒はごく薄くする（濃いと重なって真っ白に潰れる）
        ps.startColor = SIMD4(1.0, 0.45, 0.12, 0.025)
        ps.endColor = SIMD4(0.30, 0.45, 1.0, 0.0)
        ps.useIndirectDraw = true                          // 生きている粒だけ描く

        ps.addForce(.gravity(0, -55, 0))                   // 上へ（y が下向きなので負）
        ps.addForce(.noise(scale: 0.01, strength: 90))
        ps.addForce(.damping(1.0))

        system = ps
    }

    func compute() {
        guard let system else { return }
        updateParticles(system)                            // 位置の更新は GPU の中だけで完結する
    }

    func draw() {
        background(8, 10, 20)
        guard let system else { return }
        drawParticles(system)

        fill(235)
        textSize(13)
        text("\(count) 粒。位置も色も GPU の中で更新している", 14, 26)
    }
}
