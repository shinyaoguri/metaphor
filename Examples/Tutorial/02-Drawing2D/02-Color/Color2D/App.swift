import metaphor

@main
final class Color2D: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Color")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        // 引数 1 つならグレースケール。0 が黒、255 が白
        background(24)
        noStroke()

        // 1 段目: RGB の 3 チャンネル。既定の最大値は 255
        fill(230, 70, 70)
        rect(40, 40, 160, 60)
        fill(70, 200, 120)
        rect(240, 40, 160, 60)
        fill(90, 140, 240)
        rect(440, 40, 160, 60)

        // 2 段目: 第 4 引数はアルファ。重ねるほど下の色が透ける
        fill(255, 220, 80)
        rect(40, 130, 300, 60)
        fill(240, 80, 160, 128)
        rect(180, 130, 300, 60)

        // 3 段目: colorMode で解釈を切り替える。ここでは色相 0〜360、彩度・明度 0〜100
        colorMode(.hsb, 360, 100, 100, 100)
        for i in 0..<24 {
            fill(Float(i) * 15, 80, 95)
            rect(40 + Float(i) * 23, 220, 23, 50)
        }
        // 使い終わったら戻す。colorMode は以降の呼び出しすべてに効く
        colorMode(.rgb, 255)

        // 4 段目: Color 型どうしの補間。Color の各成分は colorMode と無関係に 0〜1
        let left = Color(r: 0.95, g: 0.35, b: 0.15)
        let right = Color(r: 0.15, g: 0.45, b: 0.95)
        for j in 0..<24 {
            let t = Float(j) / 23
            fill(lerpColor(left, right, t))
            rect(40 + Float(j) * 23, 290, 23, 30)
        }
    }
}
