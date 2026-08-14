import metaphor

@main
final class Stroke: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Stroke")
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(24)
        noFill()
        stroke(240)

        // 太さ。strokeWeight は以降のすべての線・輪郭に効く
        for i in 0..<5 {
            strokeWeight(Float(i) * 3 + 1)
            line(60, 50 + Float(i) * 22, 260, 50 + Float(i) * 22)
        }

        // 端点の処理。太い線ほど差が見える
        strokeWeight(20)
        strokeCap(.round)
        line(380, 55, 560, 55)
        strokeCap(.square)
        line(380, 100, 560, 100)
        strokeCap(.butt)
        line(380, 145, 560, 145)

        // 角の処理。折れ線を beginShape で描いて比べる
        strokeWeight(14)
        strokeCap(.butt)
        let joins: [StrokeJoin] = [.miter, .bevel, .round]
        for (index, join) in joins.enumerated() {
            strokeJoin(join)
            let x = 90 + Float(index) * 180
            beginShape()
            vertex(x, 300)
            vertex(x + 55, 210)
            vertex(x + 110, 300)
            endShape()
        }
    }
}
