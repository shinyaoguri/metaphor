import metaphor

@main
final class Camera: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Camera")
    }

    // シーンの中心。既定カメラが見ている場所と同じ位置に置く
    var center: Vec3 { Vec3(width / 2, height / 2, 0) }

    func draw() {
        background(18)
        ambientLight(60)
        directionalLight(0.3, 0.9, -0.4)
        noStroke()

        let t = Float(frameCount) * 0.02

        // 前半は透視投影、後半は平行投影。同じシーンの見え方の違いが分かる
        let isPerspective = (frameCount / 60) % 2 == 0
        if isPerspective {
            perspective(fov: PI / 3)
        } else {
            // ortho() の既定の範囲はキャンバスの寸法（原点が左上）なので、
            // camera() で視点を移したときは範囲も視点に合わせて指定する
            ortho(
                left: -width * 0.6, right: width * 0.6,
                bottom: height * 0.6, top: -height * 0.6
            )
        }

        // 視点をシーンのまわりで回す。center は動かさないので、常に真ん中を見続ける
        let radius: Float = 430
        camera(
            eye: SIMD3(
                center.x + cos(t) * radius,
                center.y - 150,
                center.z + sin(t) * radius
            ),
            center: SIMD3(center.x, center.y, center.z)
        )

        // 見られる側のシーン: 床と、中央の柱と、それを囲む 6 本の柱
        fill(95)
        push()
        translate(center.x, center.y + 70, center.z)
        rotateX(PI / 2)
        plane(520, 520)
        pop()

        fill(240, 190, 80)
        push()
        translate(center.x, center.y, center.z)
        box(60, 130, 60)
        pop()

        fill(110, 190, 200)
        for i in 0..<6 {
            let angle = Float(i) * TWO_PI / 6
            push()
            translate(center.x + cos(angle) * 150, center.y + 30, center.z + sin(angle) * 150)
            box(40, 70, 40)
            pop()
        }

        fill(200)
        textSize(14)
        text(isPerspective ? "perspective(fov: π/3)" : "ortho(左右上下を指定)", 22, 34)
    }
}
