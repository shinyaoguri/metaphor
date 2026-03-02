import metaphor

/// 10,000個の円と矩形を GPU Instancing で描画するデモ
///
/// GPU Instancing により、同一形状の連続描画が 1 draw call にバッチされ、
/// CPU→GPU データ転送量も大幅に削減される。
/// - 従来: 10,000 circles × 96頂点 × 24B = 23MB/frame
/// - Instancing: unit mesh 768B + 10,000 × 80B = 800KB/frame (約29倍削減)
@main final class InstancingDemo: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "GPU Instancing — 10,000 Shapes")
    }

    let circleCount = 8000
    let rectCount = 2000

    func draw() {
        background(Color(gray: 0.02))
        noStroke()

        let cx = width / 2
        let cy = height / 2
        let t = time

        // --- 8,000 circles: 渦巻き状に配置、色と大きさがゆっくり変化 ---
        for i in 0..<circleCount {
            let fi = Float(i)
            let ratio = fi / Float(circleCount)

            // 黄金角による螺旋配置
            let angle = fi * 2.39996323 + t * 0.2
            let radius = sqrt(ratio) * min(width, height) * 0.45

            let x = cx + cos(angle) * radius
            let y = cy + sin(angle) * radius

            // サイズ: 中心に近いほど大きく、外ほど小さく、時間で揺らぐ
            let sizeBase: Float = lerp(18, 4, ratio)
            let size = sizeBase * (1.0 + 0.3 * sin(fi * 0.05 + t * 2.0))

            // 色: 螺旋に沿ってHSBが変化
            let hue = fmod(ratio * 3.0 + t * 0.05, 1.0)
            let sat: Float = lerp(0.6, 1.0, ratio)
            let bri: Float = lerp(1.0, 0.5, ratio)
            let alpha: Float = lerp(0.9, 0.4, ratio)

            fill(Color(hue: hue, saturation: sat, brightness: bri, alpha: alpha))
            circle(x, y, size)
        }

        // --- 2,000 rects: グリッド状に浮遊 ---
        let cols = 50
        let rows = rectCount / cols
        let cellW = width / Float(cols)
        let cellH = height / Float(rows)

        for i in 0..<rectCount {
            let col = i % cols
            let row = i / cols
            let fi = Float(i)

            let baseX = Float(col) * cellW + cellW * 0.5
            let baseY = Float(row) * cellH + cellH * 0.5

            // 波で揺らす
            let ox = sin(baseY * 0.01 + t * 1.5) * 8
            let oy = cos(baseX * 0.01 + t * 1.2) * 8
            let x = baseX + ox
            let y = baseY + oy

            let size = cellW * 0.3 * (0.5 + 0.5 * sin(fi * 0.1 + t * 3.0))

            let hue = fmod(Float(col) / Float(cols) + t * 0.02, 1.0)
            fill(Color(hue: hue, saturation: 0.3, brightness: 0.8, alpha: 0.15))

            rectMode(.center)
            rect(x, y, size, size)
        }
    }
}
