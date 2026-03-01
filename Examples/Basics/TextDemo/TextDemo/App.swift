import metaphor

/// テキスト描画機能のデモ
///
/// textSize, textFont, textAlign, fill色によるティントなど、
/// テキストレンダリングの全機能を表示する。
@main
final class TextDemo: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Text Demo")
    }

    func draw() {
        background(Color(gray: 0.05))

        // --- セクション1: フォントサイズ比較 ---
        fill(Color(gray: 0.35))
        textSize(13)
        textFont("Menlo")
        textAlign(.left, .top)
        text("Font Sizes", 60, 30)

        noStroke()
        let sizes: [Float] = [12, 18, 24, 36, 48, 72]
        var y: Float = 60
        for size in sizes {
            fill(Color(gray: 0.9))
            textSize(size)
            textFont("Helvetica Neue")
            textAlign(.left, .baseline)
            text("\(Int(size))px — The quick brown fox", 60, y + size)
            y += size + 12
        }

        // --- セクション2: フォントファミリー ---
        let sectionX: Float = 60
        let section2Y: Float = 430
        fill(Color(gray: 0.35))
        textSize(13)
        textFont("Menlo")
        textAlign(.left, .top)
        text("Font Families", sectionX, section2Y)

        let fonts = ["Helvetica Neue", "Georgia", "Menlo", "Avenir Next", "Futura"]
        for (i, family) in fonts.enumerated() {
            let fy = section2Y + 30 + Float(i) * 50
            fill(Color(gray: 0.5))
            textSize(12)
            textFont("Menlo")
            text(family, sectionX, fy)
            fill(Color(gray: 0.95))
            textSize(28)
            textFont(family)
            text("metaphor — creative coding in Swift", sectionX + 200, fy + 4)
        }

        // --- セクション3: テキストアラインメント ---
        let alignX = width / 2
        let section3Y: Float = 720

        fill(Color(gray: 0.35))
        textSize(13)
        textFont("Menlo")
        textAlign(.left, .top)
        text("Text Alignment", 60, section3Y)

        // 中央線（ガイド）
        stroke(Color(gray: 0.2))
        strokeWeight(1)
        line(alignX, section3Y + 30, alignX, section3Y + 200)

        textSize(24)
        textFont("Helvetica Neue")
        noStroke()

        fill(Color(hue: 0.0, saturation: 0.7, brightness: 0.9))
        textAlign(.left, .baseline)
        text("Left aligned", alignX, section3Y + 60)

        fill(Color(hue: 0.33, saturation: 0.7, brightness: 0.9))
        textAlign(.center, .baseline)
        text("Center aligned", alignX, section3Y + 100)

        fill(Color(hue: 0.6, saturation: 0.7, brightness: 0.9))
        textAlign(.right, .baseline)
        text("Right aligned", alignX, section3Y + 140)

        // --- セクション4: カラフルテキスト（アニメーション） ---
        let section4Y: Float = 950
        fill(Color(gray: 0.35))
        textSize(13)
        textFont("Menlo")
        textAlign(.left, .top)
        text("Animated Color", 60, section4Y)

        textSize(48)
        textFont("Futura")
        textAlign(.center, .baseline)
        let message = "metaphor"
        let charWidth: Float = 38
        let startX = width / 2 - Float(message.count) * charWidth / 2

        for (ci, ch) in message.enumerated() {
            let hue = (Float(ci) / Float(message.count) + time * 0.15)
                .truncatingRemainder(dividingBy: 1.0)
            let yOff = sin(time * 3 + Float(ci) * 0.5) * 10
            fill(Color(hue: hue, saturation: 0.8, brightness: 1.0))
            textAlign(.center, .baseline)
            text(String(ch), startX + Float(ci) * charWidth + charWidth / 2, section4Y + 50 + yOff)
        }
    }
}
