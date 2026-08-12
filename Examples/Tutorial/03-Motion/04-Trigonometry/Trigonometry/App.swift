import metaphor

@main
final class Trigonometry: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Trigonometry")
    }

    // 左側の円の中心と半径
    let centerX: Float = 150
    let centerY: Float = 170
    let radius: Float = 96

    func draw() {
        background(24)

        // 角度はフレーム数から決める。時刻ではなくフレーム数なので、
        // 何度実行しても同じタイミングで同じ角度になる
        let angle = Float(frameCount) * 0.03

        // 円周上の点。cos が横方向、sin が縦方向を受け持つ
        let px = centerX + cos(angle) * radius
        let py = centerY + sin(angle) * radius

        // 軌道
        noFill()
        stroke(70)
        strokeWeight(1)
        circle(centerX, centerY, radius * 2)
        line(centerX - radius, centerY, centerX + radius, centerY)
        line(centerX, centerY - radius, centerX, centerY + radius)

        // 中心から点へ引いた半径。この線の縦の長さが sin、横の長さが cos
        stroke(150)
        strokeWeight(2)
        line(centerX, centerY, px, py)

        noStroke()
        fill(240, 190, 80)
        circle(px, py, 20)

        // 右側は、同じ sin を横に流した波。x が右へ進むほど過去の角度を
        // 見ていることになるので、角度から x のぶんだけ引く
        let waveLeft: Float = 320
        let waveRight = width - 20
        noFill()
        stroke(110, 200, 160)
        strokeWeight(2)
        beginShape()
        var x = waveLeft
        while x <= waveRight {
            vertex(x, centerY + sin(angle - (x - waveLeft) * 0.03) * radius)
            x += 3
        }
        endShape(.open)

        // 波の左端は、左の円で回っている点と必ず同じ高さになる
        noStroke()
        fill(240, 190, 80)
        circle(waveLeft, py, 12)

        // 位置しか手元にないときは、角度を atan2 で取り戻せる。戻る値の
        // 範囲は -PI 〜 PI なので、回り続ける angle とは一致しなくなる
        let recovered = atan2(py - centerY, px - centerX)
        textSize(13)
        fill(190)
        text("angle = \(rounded(angle)) rad", 40, 322)
        text("atan2(dy, dx) = \(rounded(recovered)) rad", 40, 342)
        fill(110, 200, 160)
        text("sin(angle - x * 0.03)", waveLeft, 322)
    }

    /// 表示用に小数 2 桁へ丸める。
    private func rounded(_ value: Float) -> Float {
        (value * 100).rounded() / 100
    }
}
