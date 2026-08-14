import metaphor

@main
final class Time: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Time")
    }

    // 1 秒あたりに進むピクセル数
    let speed: Float = 140

    // deltaTime を自分で足し込んだ距離。time * speed と同じ値になるはず
    var accumulated: Float = 0

    func draw() {
        background(24)

        // 経過時間のぶんだけ進める。フレームレートが落ちても 1 フレームの
        // deltaTime が伸びるので、見かけの速さは変わらない
        accumulated += speed * deltaTime

        // フレーム数で進める点。1 フレームにつき決まった距離だけ動くので、
        // フレームレートが変わると速さも変わる
        track(y: 96, label: "frameCount * 2.3", distance: Float(frameCount) * 2.3, color: (230, 90, 70))
        track(y: 180, label: "time * speed", distance: time * speed, color: (240, 190, 80))
        track(y: 264, label: "sum of deltaTime * speed", distance: accumulated, color: (110, 200, 160))

        fill(190)
        textSize(13)
        text("frameCount = \(frameCount)", 40, 332)
        text("time = \(rounded(time, digits: 2))s", 250, 332)
        text("deltaTime = \(rounded(deltaTime, digits: 4))s", 420, 332)
    }

    /// 1 本のトラックと、その上を走る点を描く。
    private func track(y: Float, label: String, distance: Float, color: (Float, Float, Float)) {
        let left: Float = 40
        let span = width - 80
        // 右端まで来たら左端へ戻す。余りを取るだけで往復させずに済む
        let x = left + distance.truncatingRemainder(dividingBy: span)
        let (r, g, b) = color

        stroke(70)
        strokeWeight(1)
        line(left, y, left + span, y)

        noStroke()
        fill(r, g, b)
        circle(x, y, 22)

        fill(190)
        textSize(13)
        text(label, left, y - 18)
    }

    /// 表示用に桁を丸める（画面の数字が毎フレーム暴れないように）。
    private func rounded(_ value: Float, digits: Int) -> Float {
        var scale: Float = 1
        for _ in 0..<digits { scale *= 10 }
        return (value * scale).rounded() / scale
    }
}
