import metaphor

@main
final class Easing: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Easing")
    }

    // 追従の速さ。0 に近いほどゆっくり、1 なら瞬間移動
    let easings: [Float] = [0.02, 0.06, 0.18]
    let colors: [(Float, Float, Float)] = [
        (230, 90, 70),
        (240, 190, 80),
        (110, 200, 160),
    ]

    // 追いかける側の現在位置（easings と同じ並び）
    var xs: [Float] = []
    var ys: [Float] = []

    // 3 つが共通で追う目標
    var targetX: Float = 0
    var targetY: Float = 0

    func setup() {
        // 実行するたびに同じ動きになるよう、乱数の種を固定する
        randomSeed(11)
        xs = easings.map { _ in width * 0.5 }
        ys = easings.map { _ in height * 0.5 }
        pickTarget()
    }

    func draw() {
        background(24)

        // 75 フレームごとに目標を選び直す。時刻ではなくフレーム数で決めて
        // いるので、何度実行しても同じタイミングで飛ぶ
        if frameCount % 75 == 0 {
            pickTarget()
        }

        // 目標の位置
        noFill()
        stroke(150)
        strokeWeight(2)
        circle(targetX, targetY, 40)

        for i in easings.indices {
            // イージングの本体。目標へ一気に動かさず、残りの距離の一定割合
            // だけ毎フレーム進む。距離が縮むほど進む量も減るので、自然に減速する
            xs[i] = lerp(xs[i], targetX, easings[i])
            ys[i] = lerp(ys[i], targetY, easings[i])

            let (r, g, b) = colors[i]

            // 目標との差。この線の長さが次のフレームの移動量を決める
            stroke(r, g, b, 90)
            strokeWeight(1)
            line(xs[i], ys[i], targetX, targetY)

            // 追いかける側
            noStroke()
            fill(r, g, b)
            circle(xs[i], ys[i], 24)
        }

        // どの色がどの係数かを凡例で示す。文字はいま fill 色を反映しない
        // （metaphor の既知の不具合 #516）ので、色は四角で示す
        textSize(14)
        for i in easings.indices {
            let (r, g, b) = colors[i]
            let baseline = 28 + Float(i) * 22
            fill(r, g, b)
            rect(20, baseline - 11, 12, 12)
            text("easing = \(easings[i])", 40, baseline)
        }
    }

    private func pickTarget() {
        targetX = random(80, width - 80)
        targetY = random(80, height - 80)
    }
}
