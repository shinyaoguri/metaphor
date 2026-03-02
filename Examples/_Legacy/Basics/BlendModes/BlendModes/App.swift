import metaphor

/// 全8種類のブレンドモードを比較表示するデモ
///
/// 各セルにRGB三原色のヴェン図を表示し、色の重なりがモードによってどう変わるかを見せる。
/// 背景にグラデーションを敷いて、明暗それぞれでの効果も同時に確認できる。
@main
final class BlendModes: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Blend Modes")
    }

    let modes: [(String, BlendMode)] = [
        ("alpha", .alpha),
        ("additive", .additive),
        ("multiply", .multiply),
        ("screen", .screen),
        ("subtract", .subtract),
        ("lightest", .lightest),
        ("darkest", .darkest),
        ("opaque", .opaque),
    ]

    func draw() {
        background(Color(gray: 0.1))

        let cols = 4
        let rows = 2
        let cellW = width / Float(cols)
        let cellH = height / Float(rows)

        for (i, entry) in modes.enumerated() {
            let col = i % cols
            let row = i / cols
            let panelX = Float(col) * cellW + 8
            let panelY = Float(row) * cellH + 44
            let panelW = cellW - 16
            let panelH = cellH - 52
            let cx = panelX + panelW / 2
            let cy = panelY + panelH / 2

            // ラベル
            blendMode(.alpha)
            fill(Color(gray: 0.85))
            textSize(22)
            textFont("Menlo")
            textAlign(.center, .top)
            text(entry.0, Float(col) * cellW + cellW / 2, Float(row) * cellH + 12)

            // 背景: 左暗→右明のグラデーション（各モードの明暗両方での振る舞いを見せる）
            noStroke()
            let gradSteps = 32
            let stepW = panelW / Float(gradSteps)
            for s in 0..<gradSteps {
                let t = Float(s) / Float(gradSteps - 1)
                fill(Color(gray: t * 0.85 + 0.05))
                rect(panelX + Float(s) * stepW, panelY, stepW + 1, panelH)
            }

            // パネル枠線
            blendMode(.alpha)
            stroke(Color(gray: 0.3))
            strokeWeight(1)
            noFill()
            rect(panelX, panelY, panelW, panelH)

            // ブレンドモードでRGBヴェン図を描画
            blendMode(entry.1)
            noStroke()

            let r = min(panelW, panelH) * 0.36
            let spread = r * 0.38

            // 赤（上）
            fill(Color(r: 0.9, g: 0.2, b: 0.2, a: 0.8))
            circle(cx, cy - spread, r)

            // 緑（左下）
            fill(Color(r: 0.2, g: 0.9, b: 0.2, a: 0.8))
            circle(cx - spread * 0.866, cy + spread * 0.5, r)

            // 青（右下）
            fill(Color(r: 0.2, g: 0.2, b: 0.9, a: 0.8))
            circle(cx + spread * 0.866, cy + spread * 0.5, r)
        }

        blendMode(.alpha)
    }
}
