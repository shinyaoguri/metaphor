import metaphor

/// 1 つぶんの状態。位置・速度・見た目をまとめて持つ。
struct Mover {
    var position: Vec2
    var velocity: Vec2
    var diameter: Float
    var color: Color

    /// 毎フレームの更新。描画とは分けておくと、あとから止める・数える・
    /// 並べ替えるといった操作がしやすい。
    mutating func update(bounds: Vec2) {
        position += velocity

        // 画面の外へ出たら反対側から入り直す（ラップアラウンド）
        let margin = diameter
        if position.x < -margin { position.x = bounds.x + margin }
        if position.x > bounds.x + margin { position.x = -margin }
        if position.y < -margin { position.y = bounds.y + margin }
        if position.y > bounds.y + margin { position.y = -margin }
    }
}

@main
final class ManyObjects: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Many Objects")
    }

    let moverCount = 80

    // 同じ型の値を配列で持つと、1 つ動かすコードがそのまま全体に効く
    var movers: [Mover] = []

    func setup() {
        randomSeed(3)
        noStroke()

        for _ in 0..<moverCount {
            // 個体ごとに違う値を配ると、同じ更新式でも動きに幅が出る
            let angle = random(0, TWO_PI)
            let speed = random(0.4, 2.4)
            movers.append(Mover(
                position: Vec2(random(0, width), random(0, height)),
                velocity: Vec2(cos(angle), sin(angle)) * speed,
                diameter: random(10, 38),
                color: Color(hue: random(0.5, 0.95), saturation: 0.65, brightness: 1, alpha: 0.85)
            ))
        }
    }

    func draw() {
        background(24)

        let bounds = Vec2(width, height)

        // 更新のループ
        for i in movers.indices {
            movers[i].update(bounds: bounds)
        }

        // 描画のループ
        for mover in movers {
            fill(mover.color)
            circle(mover.position.x, mover.position.y, mover.diameter)
        }

        // 円が全面に散らばるので、ラベルには下敷きを敷いておく
        fill(24, 210)
        rect(12, 12, 122, 26)
        fill(220)
        textSize(13)
        text("movers = \(movers.count)", 20, 30)
    }
}
