import metaphor

/// 30種類のイージング関数を一覧表示するギャラリー
///
/// 各セルにカーブのグラフとアニメーションする円を表示。
/// 2秒周期でループし、全イージングの違いが一目でわかる。
@main
final class EasingGallery: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Easing Gallery")
    }

    struct EasingEntry {
        let name: String
        let fn: EasingFunction
    }

    let easings: [EasingEntry] = [
        EasingEntry(name: "InQuad", fn: easeInQuad),
        EasingEntry(name: "OutQuad", fn: easeOutQuad),
        EasingEntry(name: "InOutQuad", fn: easeInOutQuad),
        EasingEntry(name: "InCubic", fn: easeInCubic),
        EasingEntry(name: "OutCubic", fn: easeOutCubic),
        EasingEntry(name: "InOutCubic", fn: easeInOutCubic),
        EasingEntry(name: "InQuart", fn: easeInQuart),
        EasingEntry(name: "OutQuart", fn: easeOutQuart),
        EasingEntry(name: "InOutQuart", fn: easeInOutQuart),
        EasingEntry(name: "InQuint", fn: easeInQuint),
        EasingEntry(name: "OutQuint", fn: easeOutQuint),
        EasingEntry(name: "InOutQuint", fn: easeInOutQuint),
        EasingEntry(name: "InSine", fn: easeInSine),
        EasingEntry(name: "OutSine", fn: easeOutSine),
        EasingEntry(name: "InOutSine", fn: easeInOutSine),
        EasingEntry(name: "InExpo", fn: easeInExpo),
        EasingEntry(name: "OutExpo", fn: easeOutExpo),
        EasingEntry(name: "InOutExpo", fn: easeInOutExpo),
        EasingEntry(name: "InCirc", fn: easeInCirc),
        EasingEntry(name: "OutCirc", fn: easeOutCirc),
        EasingEntry(name: "InOutCirc", fn: easeInOutCirc),
        EasingEntry(name: "InBack", fn: easeInBack),
        EasingEntry(name: "OutBack", fn: easeOutBack),
        EasingEntry(name: "InOutBack", fn: easeInOutBack),
        EasingEntry(name: "InElastic", fn: easeInElastic),
        EasingEntry(name: "OutElastic", fn: easeOutElastic),
        EasingEntry(name: "InOutElastic", fn: easeInOutElastic),
        EasingEntry(name: "InBounce", fn: easeInBounce),
        EasingEntry(name: "OutBounce", fn: easeOutBounce),
        EasingEntry(name: "InOutBounce", fn: easeInOutBounce),
    ]

    let cols = 6
    let rows = 5

    func draw() {
        background(Color(gray: 0.04))

        let cellW = width / Float(cols)
        let cellH = height / Float(rows)
        let padX: Float = 20
        let padY: Float = 40
        let graphW = cellW - padX * 2
        let graphH = cellH - padY - padX - 16

        // 2秒周期の往復 t: 0→1→0
        let cycle = time.truncatingRemainder(dividingBy: 4.0)
        let rawT: Float = cycle < 2.0 ? cycle / 2.0 : (4.0 - cycle) / 2.0

        for (i, entry) in easings.enumerated() {
            let col = i % cols
            let row = i / cols
            let ox = Float(col) * cellW + padX
            let oy = Float(row) * cellH + padY

            // ラベル
            fill(Color(gray: 0.7))
            textSize(18)
            textFont("Menlo")
            textAlign(.left, .top)
            text(entry.name, ox + 2, oy - 30)

            // グラフ背景
            noStroke()
            fill(Color(gray: 0.12))
            rect(ox, oy, graphW, graphH)

            // カーブ全体（薄い線）
            stroke(Color(gray: 0.4))
            strokeWeight(2)
            let steps = 50
            for s in 0..<steps {
                let t0 = Float(s) / Float(steps)
                let t1 = Float(s + 1) / Float(steps)
                let v0 = entry.fn(t0)
                let v1 = entry.fn(t1)
                line(
                    ox + t0 * graphW,
                    oy + graphH - v0 * graphH,
                    ox + t1 * graphW,
                    oy + graphH - v1 * graphH
                )
            }

            // アニメーション済み部分（明るい線）
            let easedT = entry.fn(rawT)
            stroke(Color(hue: 0.55, saturation: 0.7, brightness: 1.0, alpha: 0.9))
            strokeWeight(3)
            let animSteps = Int(rawT * Float(steps))
            for s in 0..<animSteps {
                let t0 = Float(s) / Float(steps)
                let t1 = Float(s + 1) / Float(steps)
                let v0 = entry.fn(t0)
                let v1 = entry.fn(t1)
                line(
                    ox + t0 * graphW,
                    oy + graphH - v0 * graphH,
                    ox + t1 * graphW,
                    oy + graphH - v1 * graphH
                )
            }

            // 動く円（グラフ上）
            noStroke()
            fill(Color(hue: 0.55, saturation: 0.8, brightness: 1.0))
            let dotX = ox + rawT * graphW
            let dotY = oy + graphH - easedT * graphH
            circle(dotX, dotY, 14)

            // 横バー（イージングの水平方向の動きを見せる）
            let barY = oy + graphH + 10
            fill(Color(gray: 0.2))
            rect(ox, barY, graphW, 8)
            fill(Color(hue: 0.55, saturation: 0.8, brightness: 1.0))
            circle(ox + easedT * graphW, barY + 4, 14)
        }
    }
}
