import metaphor

@main
final class Text2D: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Text")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(24)
        noStroke()
        fill(240)

        // 既定では x, y はベースライン（文字の下端を通る線）の左端
        textSize(40)
        text("metaphor", 40, 80)

        // 基準線を引いて確かめる
        stroke(90)
        strokeWeight(1)
        line(40, 80, 600, 80)
        noStroke()

        // 日本語もそのまま描ける
        fill(200)
        textSize(20)
        text("日本語も描けます", 40, 120)

        // textAlign は水平・垂直の 2 つ。中心に揃えると座標が図形と同じ感覚で扱える
        textSize(22)
        textAlign(.center, .center)
        fill(230, 160, 60)
        text("center / center", width * 0.5, 175)

        textAlign(.right, .center)
        fill(90, 180, 230)
        text("right / center", width - 40, 215)

        // 揃えは以降のすべての text() に効く。戻し忘れに注意する
        textAlign(.left, .baseline)

        // フォントはファミリー名で指定する。インストール済みのフォントから選ばれる
        fill(200)
        textFont("Helvetica")
        textSize(20)
        text("Helvetica", 40, 275)
        textFont("Courier")
        text("Courier", 200, 275)

        // 文字も図形と同じく変換の影響を受ける
        textFont("Helvetica")
        push()
        translate(400, 290)
        rotate(radians(-20))
        fill(120, 200, 160)
        textSize(26)
        text("rotated", 0, 0)
        pop()

        // 幅と高さを渡すと、その矩形の中で折り返す
        fill(150)
        textSize(14)
        text("Passing a width and a height wraps the text inside that box.", 40, 305, 260, 44)
    }
}
