import metaphor

@main
final class Window: Sketch {
    /// レンダリング解像度。絵を描く座標系の大きさで、ウィンドウの大きさとは別
    let renderWidth = 640
    let renderHeight = 360
    /// ウィンドウの大きさ = レンダリング解像度 × この係数
    let scale: Float = 0.5

    var config: SketchConfig {
        SketchConfig(
            width: renderWidth,
            height: renderHeight,
            title: "Window",
            windowScale: scale
        )
    }

    func draw() {
        background(20)

        fill(230)
        textSize(15)
        text("レンダリング解像度とウィンドウは別もの", 24, 34)

        drawScaleMap()
        drawFitDiagram()

        fill(150)
        textSize(12)
        text("width = \(Int(width))   height = \(Int(height))   windowScale = \(scale)", 24, 340)
    }

    /// 解像度とウィンドウサイズの対応。入れ子の枠で縮尺の関係を見せる
    private func drawScaleMap() {
        let x: Float = 24
        let y: Float = 56
        let w: Float = 260
        let h = w * height / width

        noFill()
        stroke(120, 190, 255)
        strokeWeight(2)
        rect(x, y, w, h)

        stroke(255, 190, 110)
        rect(x, y, w * scale, h * scale)

        noStroke()
        fill(120, 190, 255)
        textSize(12)
        text("キャンバス \(renderWidth)x\(renderHeight)", x + 4, y + h + 18)
        fill(255, 190, 110)
        let windowWidth = Int(Float(renderWidth) * scale)
        let windowHeight = Int(Float(renderHeight) * scale)
        text("ウィンドウ \(windowWidth)x\(windowHeight)", x + 4, y + h * scale - 8)

        fill(170)
        text("ウィンドウをどう伸ばしても、マウス座標は", x, y + h + 44)
        text("キャンバスの 0〜\(Int(width)) / 0〜\(Int(height)) で届く", x, y + h + 64)
    }

    /// ウィンドウの縦横比がキャンバスと違うときの余白。帯がどちら側に入るかを見せる
    private func drawFitDiagram() {
        let base: Float = 330
        drawFit(x: base, y: 66, w: 270, h: 106, label: "横長のウィンドウ")
        drawFit(x: base, y: 214, w: 145, h: 126, label: "縦長のウィンドウ")

        noStroke()
        fill(120)
        textSize(12)
        text("縦横比が違うぶんは", base + 165, 246)
        text("余白になり、絵は", base + 165, 266)
        text("歪まない", base + 165, 286)
    }

    /// 1 つのウィンドウ枠と、その中に収まるキャンバスを描く
    private func drawFit(x: Float, y: Float, w: Float, h: Float, label: String) {
        // 縦横比を保って収まる大きさ（実際のブリットパスと同じ考え方）
        let fit = min(w / width, h / height)
        let innerW = width * fit
        let innerH = height * fit
        let innerX = x + (w - innerW) / 2
        let innerY = y + (h - innerH) / 2

        noStroke()
        fill(38)
        rect(x, y, w, h)
        fill(60, 90, 130)
        rect(innerX, innerY, innerW, innerH)

        noFill()
        stroke(110)
        strokeWeight(1)
        rect(x, y, w, h)

        noStroke()
        fill(170)
        textSize(12)
        text(label, x, y - 8)
    }
}
