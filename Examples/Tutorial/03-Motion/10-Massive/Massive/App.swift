import metaphor

@main
final class Massive: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Massive")
    }

    let dotCount = 30_000

    // CircleInstance は「位置・直径・色」だけを持つ小さな値。この配列が
    // そのまま GPU へ渡せる形になっている
    var dots: [CircleInstance] = []

    // 1 粒ずつの軌道。中心からの距離と、いまの角度
    var radii: [Float] = []
    var angles: [Float] = []

    func setup() {
        randomSeed(5)
        noStroke()
        dots.reserveCapacity(dotCount)

        for i in 0..<dotCount {
            // 3 本の腕に振り分け、外側ほど遅れた角度から始めると渦を巻く
            let arm = Float(i % 3) * TWO_PI / 3
            let radius = random(22, 158) + randomGaussian() * 6
            let angle = arm + radius * 0.028 + randomGaussian() * 0.17

            radii.append(radius)
            angles.append(angle)

            dots.append(CircleInstance(
                x: 0,
                y: 0,
                diameter: random(1.2, 3.2),
                color: Color(hue: 0.54 + radius / 900, saturation: 0.75, brightness: 1, alpha: 0.5)
            ))
        }
    }

    func draw() {
        background(10)

        let center = Vec2(width * 0.5, height * 0.5)

        // 位置の更新は CPU 側。ここは普通の配列操作
        for i in dots.indices {
            angles[i] += 0.006
            dots[i].position = center + Vec2(cos(angles[i]), sin(angles[i])) * radii[i]
        }

        blendMode(.additive)

        // 3 万個を 1 回の呼び出しで渡す。円ごとの色はインスタンスが持つので、
        // fill() は「塗るかどうか」しか効かない
        circles(dots)

        blendMode(.alpha)
    }
}
