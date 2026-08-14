import metaphor

@main
final class Transform: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Transform")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(24)
        noStroke()

        // translate は「これから描くものの原点」を動かす。図形の座標は動かさない
        push()
        translate(110, 110)
        fill(230, 90, 70)
        rect(-40, -40, 80, 80)
        pop()

        // rotate は原点まわりに回す。回したい点へ translate してから rotate する
        push()
        translate(300, 110)
        rotate(radians(30))
        fill(90, 180, 230)
        rect(-40, -40, 80, 80)
        pop()

        // scale は原点からの拡大縮小。線の太さも一緒に拡大される
        push()
        translate(500, 110)
        scale(1.6, 0.8)
        fill(230, 200, 80)
        rect(-40, -40, 80, 80)
        pop()

        // 変換は積み重なる。push / pop の入れ子で「親に対する子の位置」を作れる
        push()
        translate(width * 0.5, 300)

        // 根もと
        fill(200)
        rect(-10, -12, 120, 24, 12)

        // 第 1 関節: 根もとの先端へ移動して回す
        push()
        translate(110, 0)
        rotate(radians(-45))
        fill(160)
        rect(-10, -10, 100, 20, 10)

        // 第 2 関節: さらにその先端へ。親の回転を引き継ぐ
        push()
        translate(90, 0)
        rotate(radians(-50))
        fill(120)
        rect(-8, -8, 80, 16, 8)
        pop()

        pop()
        pop()

        // pop を忘れると以降の描画すべてがずれる。ここは元の座標系に戻っている
        fill(240)
        circle(20, 20, 16)
    }
}
