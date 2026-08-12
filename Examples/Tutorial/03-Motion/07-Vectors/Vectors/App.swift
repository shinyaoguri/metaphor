import metaphor

@main
final class Vectors: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Vectors")
    }

    // 位置・速度・加速度。どれも同じ Vec2（= SIMD2<Float>）で持てる
    var position = Vec2(70, 60)
    var velocity = Vec2(4.6, 0)
    let gravity = Vec2(0, 0.34)

    let radius: Float = 22

    // 通った跡。古いものから捨てていく
    var trail: [Vec2] = []

    func draw() {
        background(24)

        // 動きの本体はこの 2 行。加速度を速度へ、速度を位置へ足すだけ
        velocity += gravity
        position += velocity

        // 壁で向きを反転する。x か y の符号を変えれば跳ね返る
        if position.x < radius || position.x > width - radius {
            velocity.x *= -1
            position.x = constrain(position.x, radius, width - radius)
        }
        if position.y > height - radius {
            velocity.y *= -1
            position.y = height - radius
        }

        trail.append(position)
        if trail.count > 90 {
            trail.removeFirst()
        }

        // 軌跡
        noStroke()
        for (i, p) in trail.enumerated() {
            fill(90, 110, 130, Float(i) / Float(trail.count) * 120)
            circle(p.x, p.y, 8)
        }

        // ベクトルはそのまま矢印として描ける。長さが速さ、向きが進む方向
        strokeWeight(3)
        stroke(240, 190, 80)
        line(position.x, position.y, position.x + velocity.x * 6, position.y + velocity.y * 6)
        stroke(110, 200, 160)
        line(position.x, position.y, position.x + gravity.x * 90, position.y + gravity.y * 90)

        noStroke()
        fill(230, 90, 70)
        circle(position.x, position.y, radius * 2)

        // magnitude はベクトルの長さ。速度の長さが「速さ」になる
        textSize(13)
        fill(240, 190, 80)
        text("velocity  (magnitude = \(rounded(velocity.magnitude)))", 20, 28)
        fill(110, 200, 160)
        text("gravity  (magnitude = \(rounded(gravity.magnitude)))", 20, 48)
    }

    /// 表示用に小数 2 桁へ丸める。
    private func rounded(_ value: Float) -> Float {
        (value * 100).rounded() / 100
    }
}
