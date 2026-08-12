import metaphor

@main
final class Lighting: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Lighting")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(10)
        noStroke()

        // 影のない場所の明るさ。これを 0 にすると光の当たらない面は真っ黒になる
        ambientLight(55)

        // 「光が進む向き」を渡す。y は画面下向きなので (0.3, 1, -0.35) は
        // 左上の手前から、奥下へ向かって差す光になる
        directionalLight(0.3, 1, -0.35, color: Color(r: 0.55, g: 0.55, b: 0.55))

        // 位置を持つ光。近くほど明るく、離れるほど falloff で減衰する。
        // 減衰は距離の 2 乗まで効くので、ピクセル単位の座標では既定値（0.1）は
        // 強すぎる。数百ピクセル先まで届かせるには 0.001 以下にする
        pointLight(180, 170, 170, color: Color(r: 1, g: 0.5, b: 0.3), falloff: 0.0006)

        // 円錐状に照らす光。位置と向き、そして開き角を持つ
        spotLight(
            470, 40, 150, 0, 1, -0.12,
            angle: 0.5, falloff: 0.0006,
            color: Color(r: 0.5, g: 0.75, b: 1)
        )

        // ハイライトの色と鋭さ。shininess が大きいほど小さく鋭く光る。
        // グレー値を渡す specular(_:) は 0〜1 で解釈される（#527）ので Color で渡す
        specular(Color(r: 0.35, g: 0.35, b: 0.35))
        shininess(64)

        // 床。plane は xy 平面なので、x 軸まわりに 90 度倒して水平にする
        fill(90)
        push()
        translate(320, 300, -60)
        rotateX(PI / 2)
        plane(900, 620)
        pop()

        // 光の違いが出るように、同じ球を横一列に並べる
        fill(205)
        for i in 0..<5 {
            push()
            translate(100 + Float(i) * 110, 235, 20)
            sphere(45)
            pop()
        }

        fill(200)
        textSize(12)
        text("ambientLight + directionalLight は全体に効く", 22, 32)
        text("pointLight（暖色・左）", 90, 110)
        text("spotLight（寒色・右）", 420, 110)
    }
}
