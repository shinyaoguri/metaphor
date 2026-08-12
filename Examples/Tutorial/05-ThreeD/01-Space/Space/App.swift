import metaphor

@main
final class Space: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Space")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(18)

        // 3D にもライトが要る。lights() は既定の平行光と環境光を入れる
        lights()
        noStroke()

        // z = 0 に置いた 140x140 の平面。中心は (150, 130)
        fill(230, 90, 70)
        push()
        translate(150, 130, 0)
        plane(140, 140)
        pop()

        // 同じ寸法・同じ位置の 2D の矩形を輪郭だけ重ねる。ずれない
        noFill()
        stroke(255)
        strokeWeight(2)
        rect(80, 60, 140, 140)

        // z だけを変えた 3 つの箱。奥（負）ほど小さく、手前（正）ほど大きい。
        // カメラは z ≈ 312 にいるので、それ以上手前へ出すと視界から消える
        noStroke()
        fill(240, 190, 80)
        for (i, z) in [Float(-300), 0, 80].enumerated() {
            push()
            translate(340 + Float(i) * 90, 200, z)
            box(70)
            pop()
        }

        fill(200)
        textSize(13)
        textAlign(.center)
        text("3D の plane(140, 140) と 2D の rect が重なる", 170, 34)
        text("z = -300", 340, 330)
        text("z = 0", 430, 330)
        text("z = +80", 520, 330)
    }
}
