import metaphor

@main
final class Mapping: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Mapping")
    }

    // 元になる値。0, 10, 20, ... 100 の 11 個
    let sampleCount = 11

    func setup() {
        noLoop()
    }

    func draw() {
        background(24)
        noStroke()

        let left: Float = 40
        let right = width - 40

        for i in 0..<sampleCount {
            let v = Float(i) * 10

            // map: 0〜100 の値を、キャンバスの左端から右端までへ引き伸ばす。
            // 等間隔の入力は等間隔のまま出てくる
            let mapped = map(v, 0, 100, left, right)

            // constrain: いったん画面の外まではみ出す範囲へ写してから、
            // 描ける範囲へ押し込む。はみ出したぶんが両端に張り付く
            let constrained = constrain(map(v, 0, 100, left - 260, right + 260), left, right)

            // lerp: 0〜1 の割合で 2 つの値の間を取る。割合の作り方を変えると
            // （ここでは 2 乗）同じ入力でも並び方が変わる
            let t = norm(v, 0, 100)
            let interpolated = lerp(left, right, t * t)

            fill(map(v, 0, 100, 70, 240), 150, map(v, 0, 100, 240, 90))
            circle(mapped, 110, 20)
            circle(constrained, 190, 20)
            circle(interpolated, 270, 20)
        }

        textSize(14)
        fill(215)
        text("map(v, 0, 100, left, right)", left, 84)
        text("constrain(map(v, 0, 100, left - 260, right + 260), left, right)", left, 164)
        text("lerp(left, right, t * t)   //  t = norm(v, 0, 100)", left, 244)

        fill(140)
        text("v = 0, 10, 20, ... 100", left, 322)
    }
}
