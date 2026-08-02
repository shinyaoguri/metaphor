import metaphor

// SVG Export
// プロッタ(AxiDraw 等)・印刷向けのジェネラティブラインアート。
// S キーで現在のフレームを真のベクタ SVG として output/plot.svg へ保存する
// (画面のラスタライズと同じ描画呼び出しから生成されるため、見たままが出力される)。

@main
final class SVGExport: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "SVGExport — press S to save")
    }

    var exportRequested = false

    func setup() {
        randomSeed(42)  // 決定論: 再実行しても同じ絵と同じ SVG になる
        noLoop()
    }

    func draw() {
        if exportRequested {
            beginSVGRecord("output/plot.svg")
        }

        background(255)
        noFill()
        stroke(0)
        strokeWeight(1)

        // 同心の変形リング: プロッタ 1 ストロークで描ける閉曲線
        let cx = width / 2
        let cy = height / 2
        for ring in 1...12 {
            let baseRadius = Float(ring) * 13
            let wobble = random(2, 9)
            let lobes = Float(Int(random(3, 8)))
            beginShape()
            let steps = 72
            for i in 0...steps {
                let angle = Float(i) / Float(steps) * TWO_PI
                let r = baseRadius + sin(angle * lobes) * wobble
                curveVertex(cx + cos(angle) * r, cy + sin(angle) * r)
            }
            endShape(.close)
        }

        // 外周の放射チック
        for i in 0..<90 {
            let angle = Float(i) / 90 * TWO_PI
            let r1: Float = 165
            let r2 = r1 + (i % 5 == 0 ? Float(12) : Float(5))
            line(cx + cos(angle) * r1, cy + sin(angle) * r1,
                 cx + cos(angle) * r2, cy + sin(angle) * r2)
        }

        if exportRequested {
            endSVGRecord()
            exportRequested = false
            print("Saved output/plot.svg")
        }
    }

    func keyPressed() {
        if key == "s" || key == "S" {
            exportRequested = true
            redraw()
        }
    }
}
