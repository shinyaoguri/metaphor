import metaphor
import Foundation

/// 中優先度6機能のショーケース
///
/// 画面を2段構成で表示:
/// - 上段: 3Dデモ（ortho + OBJ loader）を左右に並べて表示
/// - 下段: 2Dデモ4パネル（textMetrics, gradient, blendMode, strokeCap/Join）
@main
final class FeatureShowcase: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "Feature Showcase")
    }

    var loadedModel: Mesh?

    func setup() {
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let objPath = sourceDir.appendingPathComponent("Resources/diamond.obj").path
        loadedModel = loadModel(objPath)
        if loadedModel == nil {
            print("[FeatureShowcase] OBJ load failed: \(objPath)")
        }
    }

    func draw() {
        background(Color(gray: 0.12))

        // --- Phase 1: 全2Dコンテンツを先に描画 ---
        let panelY = height * 0.5
        let panelH = height * 0.5
        let panelW = width / 4

        // 下段: 2Dデモ4パネル
        drawTextMetricsDemo(panelX: 0, panelY: panelY, w: panelW, h: panelH)
        drawGradientDemo(panelX: panelW, panelY: panelY, w: panelW, h: panelH)
        drawBlendDemo(panelX: panelW * 2, panelY: panelY, w: panelW, h: panelH)
        drawStrokeDemo(panelX: panelW * 3, panelY: panelY, w: panelW, h: panelH)
        drawLabels(panelY: panelY, panelW: panelW, panelH: panelH)

        // 上段: 2Dラベル・区切り線
        draw3Dlabels()

        // --- Phase 2: 3Dコンテンツを最後に描画（Canvas3Dで上書き） ---
        draw3Ddemos()
    }

    // MARK: - Labels

    func drawLabels(panelY: Float, panelW: Float, panelH: Float) {
        blendMode(.alpha)
        noStroke()
        textFont("Menlo")
        textSize(15)
        textAlign(.center, .top)
        fill(Color(gray: 0.55))

        // 下段パネルラベル
        let labels2D = ["textAscent/Descent", "Gradient", "BlendMode", "strokeCap/Join"]
        for (i, label) in labels2D.enumerated() {
            text(label, Float(i) * panelW + panelW / 2, panelY + 6)
        }

        // 下段パネル枠線
        stroke(Color(gray: 0.22))
        strokeWeight(1)
        noFill()
        for i in 0..<4 {
            rect(Float(i) * panelW + 3, panelY + 3, panelW - 6, panelH - 6)
        }
    }

    // MARK: - 3D Labels (2D, drawn before 3D objects)

    func draw3Dlabels() {
        let halfW = width / 2

        // ラベル
        noStroke()
        fill(Color(gray: 0.55))
        textFont("Menlo")
        textSize(14)
        textAlign(.center, .top)
        text("ortho() - no perspective", halfW * 0.5, height * 0.25 + 110)

        if let model = loadedModel {
            text("OBJ loader (\(model.vertexCount) verts)", halfW * 1.5, height * 0.25 + 110)
        } else {
            fill(Color(r: 0.8, g: 0.3, b: 0.3))
            textFont("Menlo")
            textSize(18)
            textAlign(.center, .center)
            text("OBJ load failed", halfW * 1.5, height * 0.25)
        }

        // 上段の区切り線
        stroke(Color(gray: 0.22))
        strokeWeight(1)
        line(halfW, 20, halfW, height * 0.5 - 20)
        line(0, height * 0.5, width, height * 0.5)
    }

    // MARK: - 3D Demos (upper half, Canvas3D only)

    func draw3Ddemos() {
        let halfW = width / 2

        // ortho()でピクセル座標系に（view行列を単位行列化）
        camera(eye: SIMD3(0, 0, 0), center: SIMD3(0, 0, -1), up: SIMD3(0, 1, 0))
        ortho(near: -1000, far: 1000)
        lights()

        // 左: ortho() で箱を表示
        pushMatrix()
        translate(halfW * 0.5, height * 0.25, 0)
        rotateY(time * 0.6)
        rotateX(time * 0.4)
        fill(Color(r: 0.4, g: 0.75, b: 1.0))
        box(140)
        popMatrix()

        // 右: OBJ ローダーでダイヤモンドを表示
        if let model = loadedModel {
            pushMatrix()
            translate(halfW * 1.5, height * 0.25, 0)
            rotateY(time * 0.7)
            rotateX(time * 0.5)
            fill(Color(r: 0.9, g: 0.5, b: 0.2))
            scale(100, 100, 100)
            mesh(model)
            popMatrix()
        }

        perspective()
    }

    // MARK: - Panel 1: Text Metrics

    func drawTextMetricsDemo(panelX: Float, panelY: Float, w: Float, h: Float) {
        let cx = panelX + w / 2
        let baseY = panelY + h * 0.55

        textFont("Helvetica")
        textSize(48)
        textAlign(.center, .baseline)

        let asc = textAscent()
        let desc = textDescent()

        // ascent ライン (赤)
        stroke(Color(r: 0.8, g: 0.3, b: 0.3, a: 0.7))
        strokeWeight(1)
        line(panelX + 12, baseY - asc, panelX + w - 12, baseY - asc)

        // ベースライン (緑)
        stroke(Color(r: 0.3, g: 0.8, b: 0.3, a: 0.7))
        line(panelX + 12, baseY, panelX + w - 12, baseY)

        // descent ライン (青)
        stroke(Color(r: 0.3, g: 0.3, b: 0.8, a: 0.7))
        line(panelX + 12, baseY + desc, panelX + w - 12, baseY + desc)

        // テキスト
        noStroke()
        fill(.white)
        text("Metaphor", cx, baseY)

        // ラベル
        textSize(11)
        textFont("Menlo")
        textAlign(.left, .baseline)

        fill(Color(r: 0.8, g: 0.3, b: 0.3))
        text("asc:\(Int(asc))", panelX + 10, baseY - asc - 4)

        fill(Color(r: 0.3, g: 0.8, b: 0.3))
        text("base", panelX + 10, baseY - 4)

        fill(Color(r: 0.3, g: 0.3, b: 0.8))
        text("desc:\(Int(desc))", panelX + 10, baseY + desc + 14)
    }

    // MARK: - Panel 2: Gradient

    func drawGradientDemo(panelX: Float, panelY: Float, w: Float, h: Float) {
        let margin: Float = 20
        let innerY = panelY + margin + 20
        let gradW = (w - margin * 4) / 3
        let gradH = h - margin * 2 - 44

        linearGradient(
            panelX + margin, innerY, gradW, gradH,
            Color(r: 1, g: 0.2, b: 0.4), Color(r: 0.2, g: 0.4, b: 1),
            axis: .vertical
        )

        linearGradient(
            panelX + margin * 2 + gradW, innerY, gradW, gradH,
            Color(r: 1, g: 0.8, b: 0), Color(r: 0, g: 0.8, b: 0.4),
            axis: .horizontal
        )

        let radCx = panelX + margin * 3 + gradW * 2 + gradW / 2
        let radCy = innerY + gradH / 2
        let radR = min(gradW, gradH) * 0.42
        radialGradient(
            radCx, radCy, radR,
            Color(r: 1, g: 1, b: 1), Color(r: 0.1, g: 0.0, b: 0.3)
        )

        noStroke()
        fill(Color(gray: 0.4))
        textFont("Menlo")
        textSize(10)
        textAlign(.center, .top)
        text("vert", panelX + margin + gradW / 2, panelY + h - 22)
        text("horiz", panelX + margin * 2 + gradW + gradW / 2, panelY + h - 22)
        text("radial", radCx, panelY + h - 22)
    }

    // MARK: - Panel 3: BlendMode difference / exclusion

    func drawBlendDemo(panelX: Float, panelY: Float, w: Float, h: Float) {
        let halfW = w / 2
        let innerY = panelY + 28
        let innerH = h - 48

        // --- difference ---
        do {
            let cx = panelX + halfW / 2
            let cy = innerY + innerH / 2

            blendMode(.alpha)
            noStroke()
            let steps = 16
            let stepW = (halfW - 8) / Float(steps)
            for s in 0..<steps {
                let t = Float(s) / Float(steps - 1)
                fill(Color(hue: t * 0.3, saturation: 0.6, brightness: 0.8))
                rect(panelX + 4 + Float(s) * stepW, innerY, stepW + 1, innerH)
            }

            blendMode(.difference)
            noStroke()
            fill(Color(r: 1, g: 1, b: 1, a: 0.9))
            circle(cx - 20, cy, 90)
            fill(Color(r: 0.8, g: 0.4, b: 0.2, a: 0.9))
            circle(cx + 20, cy, 90)
        }

        // --- exclusion ---
        do {
            let cx = panelX + halfW + halfW / 2
            let cy = innerY + innerH / 2

            blendMode(.alpha)
            noStroke()
            let steps = 16
            let stepW = (halfW - 8) / Float(steps)
            for s in 0..<steps {
                let t = Float(s) / Float(steps - 1)
                fill(Color(hue: 0.5 + t * 0.3, saturation: 0.6, brightness: 0.8))
                rect(panelX + halfW + 4 + Float(s) * stepW, innerY, stepW + 1, innerH)
            }

            blendMode(.exclusion)
            noStroke()
            fill(Color(r: 1, g: 1, b: 1, a: 0.9))
            circle(cx - 20, cy, 90)
            fill(Color(r: 0.2, g: 0.8, b: 0.6, a: 0.9))
            circle(cx + 20, cy, 90)
        }

        blendMode(.alpha)
        noStroke()
        fill(Color(gray: 0.4))
        textFont("Menlo")
        textSize(10)
        textAlign(.center, .top)
        text("difference", panelX + halfW / 2, panelY + h - 22)
        text("exclusion", panelX + halfW + halfW / 2, panelY + h - 22)
    }

    // MARK: - Panel 4: strokeCap / strokeJoin

    func drawStrokeDemo(panelX: Float, panelY: Float, w: Float, h: Float) {
        let innerY = panelY + 30
        let sectionH = (h - 48) / 2

        // --- strokeCap ---
        let caps: [(String, StrokeCap)] = [
            ("butt", .butt), ("round", .round), ("square", .square)
        ]
        let capSpacing = w / Float(caps.count + 1)

        for (i, cap) in caps.enumerated() {
            let x = panelX + capSpacing * Float(i + 1)
            let y0 = innerY + 16
            let y1 = innerY + sectionH - 28

            noFill()
            strokeCap(cap.1)
            stroke(Color(r: 1, g: 0.6, b: 0.2))
            strokeWeight(12)
            line(x, y0, x, y1)

            // 参照マーカー
            strokeCap(.butt)
            strokeWeight(1)
            stroke(Color(gray: 0.5, alpha: 0.3))
            line(x - 14, y0, x + 14, y0)
            line(x - 14, y1, x + 14, y1)

            noStroke()
            fill(Color(gray: 0.4))
            textFont("Menlo")
            textSize(10)
            textAlign(.center, .top)
            text(cap.0, x, innerY + sectionH - 14)
        }

        // --- strokeJoin ---
        let joins: [(String, StrokeJoin)] = [
            ("miter", .miter), ("bevel", .bevel), ("round", .round)
        ]
        let joinSpacing = w / Float(joins.count + 1)
        let joinY = innerY + sectionH

        for (i, join) in joins.enumerated() {
            let cx = panelX + joinSpacing * Float(i + 1)
            let cy = joinY + sectionH / 2 - 8

            noFill()
            strokeJoin(join.1)
            strokeCap(.butt)
            stroke(Color(r: 0.3, g: 0.7, b: 1.0))
            strokeWeight(8)

            let d: Float = 32
            beginShape()
            vertex(cx - d * 1.5, cy + d)
            vertex(cx - d * 0.5, cy - d)
            vertex(cx + d * 0.5, cy + d)
            vertex(cx + d * 1.5, cy - d)
            endShape()

            noStroke()
            fill(Color(gray: 0.4))
            textFont("Menlo")
            textSize(10)
            textAlign(.center, .top)
            text(join.0, cx, joinY + sectionH - 14)
        }

        // セクションヘッダー
        noStroke()
        fill(Color(gray: 0.3))
        textFont("Menlo")
        textSize(10)
        textAlign(.left, .top)
        text("cap:", panelX + 8, innerY + 2)
        text("join:", panelX + 8, joinY + 2)

        strokeCap(.round)
        strokeJoin(.miter)
    }
}
