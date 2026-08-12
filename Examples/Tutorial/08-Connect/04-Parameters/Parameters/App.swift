import metaphor

@main
final class ParametersSketch: Sketch {
    // 宣言するだけでストアに載り、GUI にも外部からの書き込みにも同時に開かれる
    @Param(min: 3, max: 24) var count: Int = 9
    @Param(min: 20, max: 140) var radius: Float = 90
    @Param(min: 4, max: 40) var dotSize: Float = 20
    @Param var showRing: Bool = true
    @Param(choices: ["cool", "warm", "mono"]) var palette: String = "cool"

    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Parameters")
    }

    func draw() {
        background(18)

        // 宣言した全パラメータのパネルを 1 行で。返り値はパネルの矩形 (x, y, w, h)
        let panel = gui.params()

        // パネルを避けた残りの空間の真ん中に置く
        let left = panel.0 + panel.2 + 80
        push()
        translate((left + width) / 2, height / 2)

        if showRing {
            noFill()
            stroke(Color(gray: 0.45))
            strokeWeight(1)
            circle(0, 0, radius * 2)
        }

        noStroke()
        for i in 0..<count {
            let angle = Float(i) / Float(count) * TWO_PI
            fill(color(at: i))
            circle(cos(angle) * radius, sin(angle) * radius, dotSize)
        }
        pop()
    }

    /// palette は choices を持つ文字列パラメータ。宣言に無い値は書き込みが拒否される
    private func color(at index: Int) -> Color {
        let phase = Float(index) / Float(count)
        switch palette {
        case "warm":
            return Color(r: 1, g: 0.4 + phase * 0.4, b: 0.25)
        case "mono":
            let v = 0.35 + phase * 0.6
            return Color(r: v, g: v, b: v)
        default:
            return Color(r: 0.3, g: 0.6 + phase * 0.35, b: 1)
        }
    }
}
