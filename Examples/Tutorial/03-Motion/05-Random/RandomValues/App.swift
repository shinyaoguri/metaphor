import metaphor

@main
final class RandomValues: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Random Values")
    }

    let sampleCount = 6000
    let binCount = 48

    // 出た値を入れる箱。何回目の箱にいくつ入ったかを数える
    var uniform: [Int] = []
    var gaussian: [Int] = []

    func setup() {
        noLoop()

        // 種を決めておくと、実行するたびに同じ乱数列が出る。絵が毎回
        // 変わらないので、変更の影響だけを見比べられる
        randomSeed(7)

        uniform = Array(repeating: 0, count: binCount)
        gaussian = Array(repeating: 0, count: binCount)

        for _ in 0..<sampleCount {
            // 一様乱数。範囲のどこも同じくらいの確率で出る
            uniform[binIndex(random(0, 1))] += 1

            // 正規分布。平均のまわりに集まり、遠いほどまれになる
            gaussian[binIndex(0.5 + randomGaussian() * 0.13)] += 1
        }
    }

    func draw() {
        background(24)
        histogram(uniform, top: 56, barHeight: 110, color: (230, 90, 70), label: "random(0, 1)")
        histogram(gaussian, top: 218, barHeight: 110, color: (110, 200, 160), label: "0.5 + randomGaussian() * 0.13")
    }

    /// 値 0〜1 を箱の番号に直す。範囲外は両端の箱に入れる。
    private func binIndex(_ value: Float) -> Int {
        Int(constrain(value, 0, 0.999) * Float(binCount))
    }

    /// 箱の中身を棒グラフにする。棒の高さはいちばん多い箱を基準に揃える。
    private func histogram(_ bins: [Int], top: Float, barHeight: Float, color: (Float, Float, Float), label: String) {
        let left: Float = 40
        let barWidth = (width - 80) / Float(bins.count)
        let peak = Float(bins.max() ?? 1)
        let (r, g, b) = color

        noStroke()
        fill(r, g, b)
        for (i, count) in bins.enumerated() {
            let h = Float(count) / peak * barHeight
            rect(left + Float(i) * barWidth, top + barHeight - h, barWidth - 2, h)
        }

        stroke(70)
        strokeWeight(1)
        line(left, top + barHeight, width - 40, top + barHeight)

        noStroke()
        fill(r, g, b)
        textSize(14)
        text(label, left, top - 12)
    }
}
