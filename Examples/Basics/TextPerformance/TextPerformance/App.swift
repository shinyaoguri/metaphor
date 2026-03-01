import metaphor

/// Feature 10: テキストアトラス最適化
///
/// グリフアトラスによるバッチ描画で、大量のテキストを高速レンダリング。
/// マトリックス風のテキストレインでパフォーマンスを実証する。
@main
final class TextPerformanceExample: Sketch {
    struct Column {
        var y: Float
        var speed: Float
        var chars: [Character]
        var hue: Float
    }

    var columns: [Column] = []
    let charPool: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%&*<>{}[]")

    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "Text Performance (Glyph Atlas)")
    }

    func setup() {
        let spacing: Float = 18
        let colCount = Int(width / spacing)

        for i in 0..<colCount {
            let charCount = Int.random(in: 8...30)
            var chars: [Character] = []
            for _ in 0..<charCount {
                chars.append(charPool.randomElement()!)
            }
            columns.append(Column(
                y: Float.random(in: -height...0),
                speed: Float.random(in: 100...400),
                chars: chars,
                hue: Float(i) / Float(colCount)
            ))
        }
    }

    func draw() {
        background(Color(gray: 0.0, alpha: 0.15))
        noStroke()
        textSize(16)
        textAlign(.center, .top)

        let spacing: Float = 18
        let charHeight: Float = 20

        for i in 0..<columns.count {
            columns[i].y += columns[i].speed * deltaTime

            let x = Float(i) * spacing + spacing / 2

            // 画面外に出たらリセット
            let totalHeight = Float(columns[i].chars.count) * charHeight
            if columns[i].y - totalHeight > height {
                columns[i].y = Float.random(in: -height * 0.5...0)
                columns[i].speed = Float.random(in: 100...400)
                // 文字をシャッフル
                for j in 0..<columns[i].chars.count {
                    columns[i].chars[j] = charPool.randomElement()!
                }
            }

            // 各文字を描画（グリフアトラスで高速バッチ）
            for j in 0..<columns[i].chars.count {
                let y = columns[i].y - Float(j) * charHeight

                // 画面外スキップ
                guard y > -charHeight && y < height + charHeight else { continue }

                // 先頭文字は白く光る、後ろに行くほど暗くなる
                let fadeT = Float(j) / Float(columns[i].chars.count)
                if j == 0 {
                    fill(Color(r: 1.0, g: 1.0, b: 1.0, a: 0.95))
                } else {
                    let brightness = max(0.1, 1.0 - fadeT * 0.8)
                    let alpha = max(0.1, 1.0 - fadeT)
                    fill(Color(hue: 0.35, saturation: 0.8, brightness: brightness, alpha: alpha))
                }

                text(String(columns[i].chars[j]), x, y)
            }
        }

        // FPS カウンター
        fill(.white)
        textSize(14)
        textAlign(.left, .top)
        let fps = Int(1.0 / max(deltaTime, 0.001))
        let charCount = columns.reduce(0) { $0 + $1.chars.count }
        text("FPS: \(fps)  |  Characters: \(charCount)  |  Glyph Atlas Enabled", 20, 20)
    }
}
