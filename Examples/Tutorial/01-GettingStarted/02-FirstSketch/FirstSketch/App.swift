import metaphor

@main
final class FirstSketch: Sketch {
    // 起動時の設定。ウィンドウの大きさとタイトルを決める
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "First Sketch")
    }

    // 毎フレーム呼ばれる。1 回の呼び出しで 1 枚の絵を描く
    func draw() {
        background(24)
        fill(255, 140, 40)
        noStroke()
        circle(width * 0.5, height * 0.5, 160)
    }
}
