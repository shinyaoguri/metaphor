import metaphor

@main
final class ShapePrimitives: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Shape Primitives")
    }

    func setup() {
        // 動かない絵なので、1 フレームだけ描いて止める
        noLoop()
    }

    func draw() {
        background(24)
        stroke(255)
        strokeWeight(2)
        fill(60, 90, 140)

        // 上段: 中心と直径で描く円、幅と高さで描く楕円
        circle(90, 100, 90)
        ellipse(220, 100, 120, 70)

        // 矩形は既定では左上の座標と幅・高さ。第 5 引数で角を丸められる
        rect(300, 60, 110, 80)
        rect(440, 60, 110, 80, 20)

        // 下段: 頂点を直接指定する図形
        triangle(50, 300, 110, 210, 170, 300)
        quad(210, 300, 230, 220, 320, 230, 300, 300)

        // 弧は中心・大きさ・開始角・終了角（ラジアン）。mode で閉じ方が変わる
        arc(390, 260, 100, 100, 0, radians(240), .pie)

        // 線と点。点は strokeWeight の太さで描かれる
        line(460, 220, 560, 220)
        strokeWeight(10)
        point(480, 270)
        point(510, 270)
        point(540, 270)
    }
}
