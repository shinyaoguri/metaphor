import metaphor

/// スクリーンショット保存のデモ
///
/// スペースキーを押すとデスクトップにPNGスクリーンショットを保存する。
/// 画面にはジェネラティブなパターンが描かれ、保存タイミングのフィードバックも表示。
@main
final class ScreenCapture: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Screen Capture — Press SPACE to save")
    }

    var lastSaveTime: Float = -10
    var saveCount: Int = 0

    func draw() {
        background(Color(gray: 0.02))

        let cx = width / 2
        let cy = height / 2
        let t = time

        // ジェネラティブパターン: 回転するリサージュ図形
        noFill()
        strokeWeight(1.5)

        for layer in 0..<6 {
            let fl = Float(layer)
            let hue = (fl / 6.0 + t * 0.03).truncatingRemainder(dividingBy: 1.0)
            stroke(Color(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 0.7))

            let freqA = 3.0 + fl
            let freqB = 2.0 + fl * 0.7
            let phase = t * (0.3 + fl * 0.1)
            let scale = 150.0 + fl * 50.0

            beginShape()
            let steps = 200
            for s in 0...steps {
                let u = Float(s) / Float(steps) * Float.pi * 2
                let x = cx + sin(freqA * u + phase) * scale
                let y = cy + sin(freqB * u + phase * 0.7) * scale
                vertex(x, y)
            }
            endShape()
        }

        // 中央の光る点
        blendMode(.additive)
        noStroke()
        for i in 0..<8 {
            let angle = Float(i) / 8.0 * Float.pi * 2 + t * 0.5
            let r: Float = 80 + sin(t * 2 + Float(i)) * 30
            fill(Color(hue: Float(i) / 8.0, saturation: 0.6, brightness: 1.0, alpha: 0.3))
            circle(cx + cos(angle) * r, cy + sin(angle) * r, 40)
        }
        blendMode(.alpha)

        // UI: 操作説明
        fill(Color(gray: 0.4))
        textSize(14)
        textFont("Menlo")
        textAlign(.left, .top)
        text("SPACE: save screenshot to Desktop", 20, 20)
        text("Saves: \(saveCount)", 20, 42)

        // 保存フィードバック（保存後1.5秒間表示）
        let sinceLastSave = t - lastSaveTime
        if sinceLastSave < 1.5 {
            let fadeAlpha = 1.0 - sinceLastSave / 1.5
            fill(Color(r: 0.3, g: 1.0, b: 0.5, a: fadeAlpha))
            textSize(20)
            textFont("Menlo")
            textAlign(.center, .baseline)
            text("Saved!", cx, height - 40)
        }
    }

    func keyPressed() {
        if input.lastKey == " " {
            save()
            lastSaveTime = time
            saveCount += 1
        }
    }
}
