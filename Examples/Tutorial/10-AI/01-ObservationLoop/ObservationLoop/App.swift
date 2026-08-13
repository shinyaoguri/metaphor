import metaphor

@main
final class ObservationLoopSketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ObservationLoop")
    }

    /// R を押すと noise() の値をそのまま直径に使う。
    /// コンパイルも通り、値も正しいのに、画面はほとんど空になる
    var useRawNoise = false

    func setup() {
        // 種を固定する。同じ絵を何度でも観測できるようにするため
        noiseSeed(7)
    }

    func draw() {
        background(14, 16, 22)
        drawDots()
        drawCaption()
    }

    func keyPressed() {
        if key == "r" || key == "R" {
            useRawNoise.toggle()
        }
    }

    private func drawDots() {
        noStroke()
        let columns = 24
        let rows = 13
        let phase = Float(frameCount) * 0.01

        for row in 0..<rows {
            for column in 0..<columns {
                let x = (Float(column) + 0.5) * (width / Float(columns))
                let y = (Float(row) + 0.5) * (height / Float(rows))

                // noise() が返すのは 0〜1。この範囲のまま直径にすると 1 ピクセルにも満たない
                let n = noise(Float(column) * 0.18, Float(row) * 0.18, phase)
                let diameter = useRawNoise ? n : map(n, 0, 1, 3, 22)

                fill(Color(r: 0.35 + n * 0.6, g: 0.55, b: 1.0 - n * 0.35))
                circle(x, y, diameter)
            }
        }
    }

    private func drawCaption() {
        noStroke()
        fill(0, 0, 0, 190)
        rect(0, height - 36, width, 36)

        let label = useRawNoise
            ? "raw: noise() の値をそのまま直径に使っている"
            : "mapped: map(n, 0, 1, 3, 22) で見える大きさへ移した"
        fill(235)
        textSize(13)
        text("\(label)    R: 切り替え", 16, height - 13)
    }
}
