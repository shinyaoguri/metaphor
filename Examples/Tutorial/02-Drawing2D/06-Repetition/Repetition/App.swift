import metaphor

@main
final class Repetition: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Repetition")
    }

    // グリッドの列数・行数。ここだけ変えれば密度が変わる
    let columns = 16
    let rows = 9

    func setup() {
        noLoop()
    }

    func draw() {
        background(24)
        noFill()
        strokeWeight(2)

        let cellWidth = width / Float(columns)
        let cellHeight = height / Float(rows)

        // 入れ子のループでマス目をたどる。col が横、row が縦
        for row in 0..<rows {
            for col in 0..<columns {
                // マスの中心。座標計算はここ 1 か所にまとめる
                let cx = (Float(col) + 0.5) * cellWidth
                let cy = (Float(row) + 0.5) * cellHeight

                // 位置を 0〜1 に正規化してから、色と角度に配る
                let u = Float(col) / Float(columns - 1)
                let v = Float(row) / Float(rows - 1)

                stroke(80 + u * 175, 120, 240 - v * 160)

                push()
                translate(cx, cy)
                rotate((u + v) * PI * 0.5)
                rect(-cellWidth * 0.3, -cellHeight * 0.3, cellWidth * 0.6, cellHeight * 0.6)
                pop()
            }
        }
    }
}
