import metaphor

@main
final class BlendModes: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Blend Modes")
    }

    // 見比べる 4 つ。既定は .alpha
    let modes: [(BlendMode, String)] = [
        (.alpha, "alpha"),
        (.additive, "additive"),
        (.multiply, "multiply"),
        (.screen, "screen"),
    ]

    func setup() {
        noLoop()
    }

    func draw() {
        background(40)
        noStroke()

        for (index, entry) in modes.enumerated() {
            let (mode, label) = entry
            let cx = (Float(index) + 0.5) * width / Float(modes.count)

            // blendMode は以降の描画すべてに効く。区画ごとに指定し直す
            blendMode(mode)
            fill(230, 60, 60, 200)
            circle(cx - 26, 150, 110)
            fill(60, 200, 90, 200)
            circle(cx + 26, 150, 110)
            fill(70, 110, 240, 200)
            circle(cx, 195, 110)

            // ラベルは素直に重ねたいので、既定へ戻してから描く
            blendMode(.alpha)
            fill(230)
            textSize(16)
            textAlign(.center, .center)
            text(label, cx, 300)
        }
    }
}
