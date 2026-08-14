import metaphor

@main
final class Shadow: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Shadow")
    }

    func setup() {
        noLoop()
        // シャドウマップを有効にする。解像度を上げるほど輪郭が滑らかになる
        enableShadows(resolution: 2048)
        // 面が自分自身に落とす縞（シャドウアクネ）が出るときに調整する
        shadowBias(0.002)
    }

    func draw() {
        background(12)
        noStroke()

        ambientLight(45)
        // 影を落とすのは平行光。「光が進む向き」なので y が正なら上から差す。
        // z を負にすると手前から奥へ差し、こちらを向いた面が明るくなる
        directionalLight(0.3, 1, -0.35)

        // 影を受ける床
        fill(120)
        push()
        translate(320, 300, -40)
        rotateX(PI / 2)
        plane(900, 700)
        pop()

        // 影を落とす 3 つの形。床からの高さを変えてある
        fill(235, 180, 90)
        push()
        translate(180, 215, 20)
        rotateY(0.6)
        box(90)
        pop()

        fill(110, 190, 200)
        push()
        translate(330, 190, 40)
        sphere(52)
        pop()

        fill(230, 90, 70)
        push()
        translate(470, 220, 0)
        cylinder(radius: 40, height: 110)
        pop()

        fill(200)
        textSize(12)
        text("enableShadows() + directionalLight(0.3, 1, -0.35)", 22, 34)
    }
}
