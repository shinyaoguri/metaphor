import metaphor

@main
final class Transform3D: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Transform 3D")
    }

    func draw() {
        background(18)
        lights()
        noStroke()

        // 撮り直しても同じ絵になるよう、時刻ではなくフレーム数で回す。
        // 最初のフレームから傾いているように 0.7 ラジアンだけ足しておく
        let a = 0.7 + Float(frameCount) * 0.02

        // 上の段: 同じ形を x / y / z 軸まわりに回す。板と目印の球で向きが分かる
        marker(at: 110, y: 100, label: "rotateX(a)") { rotateX(a) }
        marker(at: 320, y: 100, label: "rotateY(a)") { rotateY(a) }
        marker(at: 530, y: 100, label: "rotateZ(a)") { rotateZ(a) }

        // 下の段: 入れ子。親の座標系の中で子が回る
        push()
        translate(320, 265, 0)

        fill(240, 190, 80)
        sphere(34)                    // 中心

        rotateY(a)                    // ここから先は「回った座標系」
        translate(130, 0, 0)
        fill(110, 190, 200)
        sphere(22)                    // 中心のまわりを回る球

        rotateY(a * 3)                // さらにその中で回る
        translate(48, 0, 0)
        fill(230, 90, 70)
        sphere(11)                    // 球のまわりを回る球
        pop()

        fill(190)
        textSize(12)
        text("入れ子の座標系: 親が回ると子もついて回る", 200, 348)
    }

    /// 板と目印を 1 組描く。rotate の掛け方だけを呼び出し側から差し込む。
    private func marker(at x: Float, y: Float, label: String, rotation: () -> Void) {
        push()
        translate(x, y, 0)
        rotation()

        fill(235, 180, 90)
        box(110, 110, 8)              // 薄い板。向きが変わると見え方が変わる

        translate(0, -55, 0)          // 板の「上端」に目印を置く
        fill(230, 90, 70)
        sphere(13)
        pop()

        pushStyle()
        fill(190)
        textSize(12)
        text(label, x - 34, y + 92)
        popStyle()
    }
}
