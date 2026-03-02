import metaphor

/// Feature 8: Tween/Timeline エンジン
///
/// さまざまなイージング関数で図形が動くデモ。
/// クリックで新しいアニメーションを再生する。
@main
final class TweenAnimationExample: Sketch {
    // 各行のイージング名と関数
    let easings: [(String, EasingFunction)] = [
        ("easeInOutCubic", easeInOutCubic),
        ("easeOutElastic", easeOutElastic),
        ("easeOutBounce", easeOutBounce),
        ("easeInOutBack", easeInOutBack),
        ("easeInQuart", easeInQuart),
        ("easeOutExpo", easeOutExpo),
        ("easeInOutSine", easeInOutSine),
        ("easeOutCirc", easeOutCirc),
    ]

    var positions: [Tween<Float>] = []
    var colors: [Tween<Color>] = []

    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "Tween Animation")
    }

    func setup() {
        startTweens()
    }

    func startTweens() {
        positions.removeAll()
        colors.removeAll()

        let startX: Float = 200
        let endX: Float = width - 200

        for i in 0..<easings.count {
            let (_, fn) = easings[i]
            let hue = Float(i) / Float(easings.count)

            // 位置のトゥイーン（往復）
            let posTween = tween(from: startX, to: endX, duration: 2.0, easing: fn)
            posTween.yoyo().repeatCount(999)
            posTween.start()
            positions.append(posTween)

            // 色のトゥイーン
            let fromColor = Color(hue: hue, saturation: 0.8, brightness: 1.0)
            let toColor = Color(hue: hue + 0.5, saturation: 0.9, brightness: 0.8)
            let colorTween = tween(from: fromColor, to: toColor, duration: 2.0, easing: fn)
            colorTween.yoyo().repeatCount(999)
            colorTween.start()
            colors.append(colorTween)
        }
    }

    func mousePressed() {
        startTweens()
    }

    func draw() {
        background(Color(gray: 0.05))

        let rowHeight = (height - 120) / Float(easings.count)
        let circleSize: Float = min(rowHeight * 0.6, 50)

        for i in 0..<easings.count {
            let (name, _) = easings[i]
            let y = 80 + Float(i) * rowHeight + rowHeight / 2

            // ラベル
            fill(Color(gray: 0.4))
            textSize(13)
            textAlign(.right, .center)
            text(name, 170, y)

            // トラックライン
            stroke(Color(gray: 0.15))
            strokeWeight(1)
            line(200, y, width - 200, y)
            noStroke()

            // アニメーションする円
            let x = positions[i].value
            fill(colors[i].value)
            circle(x, y, circleSize)
        }

        // タイトル
        fill(.white)
        textSize(18)
        textAlign(.center, .top)
        text("Tween Engine - Click to restart", width / 2, 20)
    }
}
