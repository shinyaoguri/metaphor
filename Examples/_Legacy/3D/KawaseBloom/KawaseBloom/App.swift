import metaphor

/// Feature 3: Kawase/Dual-filter ブラー（Bloom エフェクト）
///
/// 発光するオブジェクトに Kawase ベースの高速ブルームを適用。
/// 従来の Gaussian に比べ 10 倍高速。
@main
final class KawaseBloomExample: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "Kawase Bloom")
    }

    func setup() {
        // Bloom ポストエフェクトを有効化（内部で Kawase ブラーを使用）
        addPostEffect(.bloom(intensity: 1.5, threshold: 0.4))
    }

    func draw() {
        background(Color(gray: 0.01))
        lights()

        // --- 発光する球体群 ---
        let count = 12
        for i in 0..<count {
            let angle = Float(i) / Float(count) * Float.pi * 2 + time * 0.3
            let radius: Float = 300
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            let y = sin(time * 2 + Float(i)) * 80

            pushMatrix()
            translate(x, y, z)

            // HSB で虹色に光る
            let hue = (Float(i) / Float(count) + time * 0.05)
                .truncatingRemainder(dividingBy: 1.0)
            fill(Color(hue: hue, saturation: 0.6, brightness: 1.0))

            // Emissive を高くして Bloom の閾値を超えさせる
            emissive(Color(hue: hue, saturation: 0.8, brightness: 0.9))
            sphere(40)
            emissive(0)

            popMatrix()
        }

        // --- 中央の大きな光源 ---
        pushMatrix()
        let pulse = 0.8 + sin(time * 3) * 0.2
        scale(pulse)
        fill(Color(r: 1.0, g: 0.95, b: 0.8))
        emissive(Color(r: 1.0, g: 0.9, b: 0.7))
        sphere(80)
        emissive(0)
        popMatrix()

        // --- 床面 ---
        pushMatrix()
        translate(0, -200, 0)
        rotateX(-Float.pi / 2)
        fill(Color(gray: 0.08))
        plane(1200, 1200)
        popMatrix()
    }
}
