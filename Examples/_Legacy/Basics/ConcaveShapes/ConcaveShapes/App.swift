import metaphor

/// Feature 1 デモ: 凹多角形テッセレーション & 穴あき多角形
///
/// - 左: アニメーションする星型（凹多角形）
/// - 中: L字型 + 穴あき多角形
/// - 右: beginContour で穴を開けた多角形
@main
final class ConcaveShapes: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Concave Shapes — Ear-Clip Tessellation")
    }

    func draw() {
        background(Color(r: 0.06, g: 0.06, b: 0.1))

        let t = time
        let cx = width / 2
        let cy = height / 2

        // ── 左: アニメーション星型 ──
        drawAnimatedStar(x: cx - 450, y: cy - 150, t: t)

        // ── 中上: L字型（凹多角形）──
        drawLShape(x: cx, y: cy - 200, t: t)

        // ── 中下: 矢印型 ──
        drawArrow(x: cx, y: cy + 200, t: t)

        // ── 右: 穴あき多角形 (beginContour) ──
        drawHoledShape(x: cx + 450, y: cy - 150, t: t)

        // ── 下: 複数穴の多角形 ──
        drawMultiHole(x: cx, y: cy + 500, t: t)

        // UI
        fill(Color(r: 0.5, g: 0.5, b: 0.6))
        noStroke()
        textSize(14)
        textFont("Menlo")
        textAlign(.left, .top)
        text("Star (concave)", 80, 30)
        text("L-shape / Arrow", cx - 80, 30)
        text("Contour holes", cx + 340, 30)
    }

    // MARK: - アニメーション星型

    private func drawAnimatedStar(x: Float, y: Float, t: Float) {
        let points = 7
        let outerR: Float = 160
        let innerR: Float = 70 + sin(t * 1.5) * 30

        var verts: [(Float, Float)] = []
        for i in 0..<(points * 2) {
            let angle = Float(i) / Float(points * 2) * Float.pi * 2 - Float.pi / 2 + t * 0.3
            let r = i % 2 == 0 ? outerR : innerR
            verts.append((x + cos(angle) * r, y + sin(angle) * r))
        }

        noStroke()
        fill(Color(r: 1.0, g: 0.75, b: 0.2, a: 0.9))
        polygon(verts)

        // アウトライン
        noFill()
        stroke(Color(r: 1.0, g: 0.9, b: 0.5))
        strokeWeight(2)
        polygon(verts)
    }

    // MARK: - L字型

    private func drawLShape(x: Float, y: Float, t: Float) {
        let s: Float = 60
        let verts: [(Float, Float)] = [
            (x - s * 2, y - s * 2),
            (x,         y - s * 2),
            (x,         y),
            (x + s * 2, y),
            (x + s * 2, y + s),
            (x - s * 2, y + s)
        ]

        noStroke()
        let hue = fmod(t * 0.1, 1.0)
        colorMode(.hsb, 1)
        fill(hue, 0.7, 0.9)
        polygon(verts)
        colorMode(.rgb, 255)

        // アウトライン
        noFill()
        stroke(Color(gray: 1.0, alpha: 0.5))
        strokeWeight(1.5)
        polygon(verts)
    }

    // MARK: - 矢印型

    private func drawArrow(x: Float, y: Float, t: Float) {
        let bounce = sin(t * 2) * 20

        let verts: [(Float, Float)] = [
            (x - 120, y - 30),
            (x + 40,  y - 30),
            (x + 40,  y - 70),
            (x + 140 + bounce, y),
            (x + 40,  y + 70),
            (x + 40,  y + 30),
            (x - 120, y + 30)
        ]

        noStroke()
        fill(Color(r: 0.3, g: 0.8, b: 0.5, a: 0.9))
        polygon(verts)

        noFill()
        stroke(Color(r: 0.5, g: 1.0, b: 0.7))
        strokeWeight(2)
        polygon(verts)
    }

    // MARK: - 穴あき多角形 (beginContour)

    private func drawHoledShape(x: Float, y: Float, t: Float) {
        let r: Float = 160
        let holeR: Float = 50 + sin(t * 2) * 20

        // 外周: 六角形
        noStroke()
        fill(Color(r: 0.6, g: 0.4, b: 0.9, a: 0.9))

        beginShape()
        for i in 0..<6 {
            let angle = Float(i) / 6 * Float.pi * 2 - Float.pi / 2
            vertex(x + cos(angle) * r, y + sin(angle) * r)
        }

        // 穴: 小さな正方形（CW方向）
        beginContour()
        let hx = x + cos(t) * 30
        let hy = y + sin(t) * 30
        vertex(hx - holeR, hy - holeR)
        vertex(hx - holeR, hy + holeR)
        vertex(hx + holeR, hy + holeR)
        vertex(hx + holeR, hy - holeR)
        endContour()

        endShape(.close)

        // アウトライン
        noFill()
        stroke(Color(r: 0.8, g: 0.6, b: 1.0))
        strokeWeight(2)

        beginShape()
        for i in 0..<6 {
            let angle = Float(i) / 6 * Float.pi * 2 - Float.pi / 2
            vertex(x + cos(angle) * r, y + sin(angle) * r)
        }
        endShape(.close)
    }

    // MARK: - 複数穴

    private func drawMultiHole(x: Float, y: Float, t: Float) {
        noStroke()
        fill(Color(r: 0.2, g: 0.6, b: 0.9, a: 0.85))

        let w: Float = 500
        let h: Float = 160

        beginShape()
        // 外周: 丸みのない長方形
        vertex(x - w / 2, y - h / 2)
        vertex(x + w / 2, y - h / 2)
        vertex(x + w / 2, y + h / 2)
        vertex(x - w / 2, y + h / 2)

        // 穴1: 左側の円形穴
        beginContour()
        let hole1X = x - 160
        let hole1R: Float = 40 + sin(t * 3) * 10
        for i in stride(from: 15, through: 0, by: -1) {
            let a = Float(i) / 16 * Float.pi * 2
            vertex(hole1X + cos(a) * hole1R, y + sin(a) * hole1R)
        }
        endContour()

        // 穴2: 中央のダイヤモンド
        beginContour()
        let hole2R: Float = 45
        vertex(x, y - hole2R)
        vertex(x - hole2R, y)
        vertex(x, y + hole2R)
        vertex(x + hole2R, y)
        endContour()

        // 穴3: 右側の三角形穴
        beginContour()
        let hole3X = x + 160
        let hole3R: Float = 40
        vertex(hole3X, y - hole3R)
        vertex(hole3X - hole3R, y + hole3R)
        vertex(hole3X + hole3R, y + hole3R)
        endContour()

        endShape(.close)

        // アウトライン
        noFill()
        stroke(Color(r: 0.4, g: 0.8, b: 1.0))
        strokeWeight(1.5)
        rect(x - w / 2, y - h / 2, w, h)
    }
}
