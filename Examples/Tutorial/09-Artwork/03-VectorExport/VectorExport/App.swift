import metaphor

@main
final class VectorExportSketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "VectorExport")
    }

    let svgPath = "output/plot.svg"

    var exportRequested = false
    var status = "S: SVG を書き出す"

    func setup() {
        noiseSeed(3)
        // 線画は動かさない。1 フレームだけ描いて止まる
        noLoop()
    }

    func draw() {
        // 記録するのは「絵そのもの」だけ。ここから endSVGRecord() までの描画は、
        // 画面へのラスタライズと同時に SVG へも記録される
        if exportRequested {
            beginSVGRecord(svgPath)
        }

        background(255)
        drawPlot()

        if exportRequested {
            endSVGRecord()
            exportRequested = false
            status = "\(svgPath) に書き出しました"
        }

        // 画面のための案内。記録の外に置いてあるので SVG には入らない
        drawStatusBar()
    }

    func keyPressed() {
        if key == "s" || key == "S" {
            exportRequested = true
            // noLoop() 中なので、書き出したいフレームを自分で 1 枚描かせる
            redraw()
        }
    }

    /// ペンプロッタで引ける線だけの絵。塗りを使わず、
    /// 1 本が 1 ストロークになる開いた曲線で作る
    private func drawPlot() {
        noFill()
        stroke(20)
        strokeWeight(1)

        rect(24, 24, width - 48, height - 48)

        let lines = 26
        let steps = 56
        for row in 0..<lines {
            let baseY = map(Float(row), 0, Float(lines - 1), 56, height - 56)
            // 下の行ほど大きく揺れる
            let amount = map(Float(row), 0, Float(lines - 1), 3, 26)
            beginShape()
            for step in 0...steps {
                let x = map(Float(step), 0, Float(steps), 44, width - 44)
                let displacement = (noise(x * 0.006, baseY * 0.02) - 0.5) * amount * 2
                curveVertex(x, baseY + displacement)
            }
            endShape()
        }
    }

    private func drawStatusBar() {
        noStroke()
        fill(0, 0, 0, 180)
        rect(0, height - 30, width, 30)
        fill(240)
        textSize(13)
        textAlign(.left, .center)
        text(status, 18, height - 15)
    }
}
