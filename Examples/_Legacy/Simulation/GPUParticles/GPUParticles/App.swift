import metaphor

/// Feature 1: GPU パーティクルシステム + Feature 4: Transform Stack
///
/// Metal Compute で 100万パーティクルをリアルタイム処理。
/// 重力・渦・ノイズの合成フォースで銀河のような動きを作る。
@main
final class GPUParticlesExample: Sketch {
    var ps: ParticleSystem!

    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "GPU Particles (1M)")
    }

    func setup() {
        ps = try! createParticleSystem(count: 1_000_000)

        // 球体状に放出（広めに散らす）
        ps.emitter = .sphere(x: 0, y: 0, z: 0, radius: 2.0)
        ps.emissionRate = 300_000
        ps.particleLife = 5.0
        ps.particleSize = 0.02

        // 色: 青 → 透明な暖色
        ps.startColor = SIMD4<Float>(0.3, 0.6, 1.0, 0.8)
        ps.endColor = SIMD4<Float>(1.0, 0.9, 0.7, 0.0)

        // フォース: 渦 + ノイズ + 軽い減衰
        ps.addForce(.vortex(x: 0, y: 0, z: 0, strength: 2.0))
        ps.addForce(.noise(scale: 0.3, strength: 1.0))
        ps.addForce(.damping(0.5))
    }

    func compute() {
        updateParticles(ps)
    }

    func draw() {
        background(Color(gray: 0.01))

        // Feature 4: Transform Stack — push/pop で 2D/3D 状態を一括管理
        push()

        // カメラをゆっくり回転
        let camDist: Float = 10.0
        let camAngle = time * 0.15
        camera(
            eye: SIMD3(cos(camAngle) * camDist, sin(time * 0.1) * 3.0, sin(camAngle) * camDist),
            center: SIMD3(0, 0, 0)
        )

        drawParticles(ps)

        pop()

        // 2D オーバーレイ（push/pop で 3D 状態が復元されている）
        fill(.white)
        textSize(14)
        textAlign(.left, .top)
        text("Particles: 1,000,000", 20, 20)
        text("FPS: \(Int(1.0 / max(deltaTime, 0.001)))", 20, 40)
    }
}
