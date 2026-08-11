import metaphor

@main
final class SketchSkeleton: Sketch {
    // config: 起動時に一度だけ読まれる設定。ウィンドウの大きさとタイトルを決める
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Sketch Skeleton")
    }

    // draw() をまたいで持ち越したい値は、プロパティとして持つ
    var angle: Float = 0

    // setup(): 起動時に一度だけ呼ばれる。描き始める前の準備をここに書く
    func setup() {
        noStroke()
        fill(255, 140, 40)
    }

    // draw(): 毎フレーム呼ばれる。1 回の呼び出しで 1 枚の絵を描く
    func draw() {
        background(24)
        push()
        translate(width * 0.5, height * 0.5)
        rotate(angle)
        rect(-60, -60, 120, 120)
        pop()
        angle += 0.01
    }
}
