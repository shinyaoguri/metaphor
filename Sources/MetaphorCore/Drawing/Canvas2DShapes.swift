import Metal
import simd

// MARK: - シェイプ

extension Canvas2D {

    /// 現在の rectMode に応じた座標解釈で矩形を描画します。
    /// - Parameters:
    ///   - x: x座標（または第1コーナーx、または中心x。rectMode に依存）。
    ///   - y: y座標（または第1コーナーy、または中心y。rectMode に依存）。
    ///   - w: 幅（または第2コーナーx、または半幅。rectMode に依存）。
    ///   - h: 高さ（または第2コーナーy、または半高さ。rectMode に依存）。
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        let rx: Float, ry: Float, rw: Float, rh: Float
        switch currentRectMode {
        case .corner:
            rx = x; ry = y; rw = w; rh = h
        case .corners:
            rx = min(x, w); ry = min(y, h); rw = abs(w - x); rh = abs(h - y)
        case .center:
            rx = x - w / 2; ry = y - h / 2; rw = w; rh = h
        case .radius:
            rx = x - w; ry = y - h; rw = w * 2; rh = h * 2
        }
        if hasFill {
            // GPU インスタンシング: 単位矩形 [-0.5, 0.5]² を中心+サイズに変換
            let centerX = rx + rw * 0.5
            let centerY = ry + rh * 0.5
            addShapeInstance(.rect, cx: centerX, cy: centerY, sx: rw, sy: rh)
        }
        if hasStroke {
            flushInstancedBatch()
            strokePolyline([
                (rx, ry), (rx + rw, ry), (rx + rw, ry + rh), (rx, ry + rh)
            ], closed: true)
        }
    }

    /// 均一な角丸半径で角丸矩形を描画します。
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///   - r: 四隅すべてに適用される角丸半径。
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        rect(x, y, w, h, r, r, r, r)
    }

    /// 個別の角丸半径で角丸矩形を描画します。
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///   - tl: 左上の角丸半径。
    ///   - tr: 右上の角丸半径。
    ///   - br: 右下の角丸半径。
    ///   - bl: 左下の角丸半径。
    public func rect(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ tl: Float, _ tr: Float, _ br: Float, _ bl: Float
    ) {
        if tl <= 0 && tr <= 0 && br <= 0 && bl <= 0 {
            rect(x, y, w, h)
            return
        }

        let rx: Float, ry: Float, rw: Float, rh: Float
        switch currentRectMode {
        case .corner:
            rx = x; ry = y; rw = w; rh = h
        case .corners:
            rx = min(x, w); ry = min(y, h); rw = abs(w - x); rh = abs(h - y)
        case .center:
            rx = x - w / 2; ry = y - h / 2; rw = w; rh = h
        case .radius:
            rx = x - w; ry = y - h; rw = w * 2; rh = h * 2
        }

        let maxR = min(rw, rh) * 0.5
        let rtl = min(max(tl, 0), maxR)
        let rtr = min(max(tr, 0), maxR)
        let rbr = min(max(br, 0), maxR)
        let rbl = min(max(bl, 0), maxR)

        let segments = 8
        var outline: [(Float, Float)] = []
        outline.reserveCapacity((segments + 1) * 4)

        for j in 0...segments {
            let a = Float.pi + Float.pi * 0.5 * Float(j) / Float(segments)
            outline.append((rx + rtl + rtl * cos(a), ry + rtl + rtl * sin(a)))
        }
        for j in 0...segments {
            let a = Float.pi * 1.5 + Float.pi * 0.5 * Float(j) / Float(segments)
            outline.append((rx + rw - rtr + rtr * cos(a), ry + rtr + rtr * sin(a)))
        }
        for j in 0...segments {
            let a = Float.pi * 0.5 * Float(j) / Float(segments)
            outline.append((rx + rw - rbr + rbr * cos(a), ry + rh - rbr + rbr * sin(a)))
        }
        for j in 0...segments {
            let a = Float.pi * 0.5 + Float.pi * 0.5 * Float(j) / Float(segments)
            outline.append((rx + rbl + rbl * cos(a), ry + rh - rbl + rbl * sin(a)))
        }

        if hasFill && outline.count >= 3 {
            let cx = rx + rw * 0.5
            let cy = ry + rh * 0.5
            for i in 0..<outline.count {
                let next = (i + 1) % outline.count
                addTriangle(cx, cy, outline[i].0, outline[i].1, outline[next].0, outline[next].1, fillColor)
            }
        }

        if hasStroke && outline.count >= 2 {
            strokePolyline(outline, closed: true)
        }
    }

    /// ``rect(_:_:_:_:)`` の簡易版。幅と高さが等しい正方形を描画します。
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    ///   - size: 正方形の辺の長さ。
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        rect(x, y, size, size)
    }

    /// 4つの頂点で定義される四角形を描画します。
    /// - Parameters:
    ///   - x1: 第1頂点のx座標。
    ///   - y1: 第1頂点のy座標。
    ///   - x2: 第2頂点のx座標。
    ///   - y2: 第2頂点のy座標。
    ///   - x3: 第3頂点のx座標。
    ///   - y3: 第3頂点のy座標。
    ///   - x4: 第4頂点のx座標。
    ///   - y4: 第4頂点のy座標。
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        if hasFill {
            addTriangle(x1, y1, x2, y2, x3, y3, fillColor)
            addTriangle(x1, y1, x3, y3, x4, y4, fillColor)
        }
        if hasStroke {
            strokeLine(x1, y1, x2, y2)
            strokeLine(x2, y2, x3, y3)
            strokeLine(x3, y3, x4, y4)
            strokeLine(x4, y4, x1, y1)
        }
    }

    // MARK: - グラデーション

    /// 線形グラデーションで塗りつぶされた矩形を描画します。
    /// - Parameters:
    ///   - x: 矩形のx座標。
    ///   - y: 矩形のy座標。
    ///   - w: 矩形の幅。
    ///   - h: 矩形の高さ。
    ///   - color1: グラデーションの開始色。
    ///   - color2: グラデーションの終了色。
    ///   - axis: グラデーションの方向。
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ color1: Color, _ color2: Color,
        axis: GradientAxis = .vertical
    ) {
        let sc1 = color1.simd
        let sc2 = color2.simd

        let tl: SIMD4<Float>, tr: SIMD4<Float>, bl: SIMD4<Float>, br: SIMD4<Float>
        switch axis {
        case .vertical:
            tl = sc1; tr = sc1; bl = sc2; br = sc2
        case .horizontal:
            tl = sc1; tr = sc2; bl = sc1; br = sc2
        case .diagonal:
            tl = sc1; tr = lerp(sc1, sc2, 0.5)
            bl = lerp(sc1, sc2, 0.5); br = sc2
        }

        addVertex(x, y, tl)
        addVertex(x + w, y, tr)
        addVertex(x + w, y + h, br)

        addVertex(x, y, tl)
        addVertex(x + w, y + h, br)
        addVertex(x, y + h, bl)
    }

    /// 指定した中心点に放射状グラデーションを描画します。
    /// - Parameters:
    ///   - cx: 中心のx座標。
    ///   - cy: 中心のy座標。
    ///   - radius: グラデーションの外側半径。
    ///   - innerColor: 中心の色。
    ///   - outerColor: 外縁の色。
    ///   - segments: 円の近似に使用するセグメント数。
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        let sc1 = innerColor.simd
        let sc2 = outerColor.simd
        let segs = max(segments, 6)

        for i in 0..<segs {
            let a1 = Float(i) / Float(segs) * Float.pi * 2
            let a2 = Float(i + 1) / Float(segs) * Float.pi * 2

            let ex1 = cx + cos(a1) * radius
            let ey1 = cy + sin(a1) * radius
            let ex2 = cx + cos(a2) * radius
            let ey2 = cy + sin(a2) * radius

            addVertex(cx, cy, sc1)
            addVertex(ex1, ey1, sc2)
            addVertex(ex2, ey2, sc2)
        }
    }

    /// 現在の ellipseMode に応じた座標解釈で楕円を描画します。
    /// - Parameters:
    ///   - x: x座標（またはコーナーx、または中心x。ellipseMode に依存）。
    ///   - y: y座標（またはコーナーy、または中心y。ellipseMode に依存）。
    ///   - w: 幅（または第2コーナーx、またはx半径。ellipseMode に依存）。
    ///   - h: 高さ（または第2コーナーy、またはy半径。ellipseMode に依存）。
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        let cx: Float, cy: Float, rx: Float, ry: Float
        switch currentEllipseMode {
        case .center:
            cx = x; cy = y; rx = w * 0.5; ry = h * 0.5
        case .radius:
            cx = x; cy = y; rx = w; ry = h
        case .corner:
            rx = w * 0.5; ry = h * 0.5; cx = x + rx; cy = y + ry
        case .corners:
            rx = abs(w - x) * 0.5; ry = abs(h - y) * 0.5
            cx = min(x, w) + rx; cy = min(y, h) + ry
        }

        if hasFill {
            // GPU インスタンシング: 単位円メッシュ（直径=1）を (rx*2, ry*2) にスケーリング
            addShapeInstance(.ellipse, cx: cx, cy: cy, sx: rx * 2, sy: ry * 2)
        }
        if hasStroke {
            // 描画順序を保つため、ストローク前にインスタンスバッチをフラッシュ
            flushInstancedBatch()
            let step = Float.pi * 2.0 / Float(ellipseSegments)
            for i in 0..<ellipseSegments {
                let a0 = step * Float(i)
                let a1 = step * Float(i + 1)
                let px0 = cx + rx * cos(a0)
                let py0 = cy + ry * sin(a0)
                let px1 = cx + rx * cos(a1)
                let py1 = cy + ry * sin(a1)
                strokeLine(px0, py0, px1, py1)
            }
        }
    }

    /// ``ellipse(_:_:_:_:)`` の簡易版。幅と高さが等しい円を描画します。
    /// - Parameters:
    ///   - x: 中心のx座標。
    ///   - y: 中心のy座標。
    ///   - diameter: 円の直径。
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        ellipse(x, y, diameter, diameter)
    }

    /// 2点間の線分を描画します。
    /// - Parameters:
    ///   - x1: 始点のx座標。
    ///   - y1: 始点のy座標。
    ///   - x2: 終点のx座標。
    ///   - y2: 終点のy座標。
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        strokeLine(x1, y1, x2, y2)
    }

    /// 3つの頂点で定義される三角形を描画します。
    /// - Parameters:
    ///   - x1: 第1頂点のx座標。
    ///   - y1: 第1頂点のy座標。
    ///   - x2: 第2頂点のx座標。
    ///   - y2: 第2頂点のy座標。
    ///   - x3: 第3頂点のx座標。
    ///   - y3: 第3頂点のy座標。
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        if hasFill {
            addTriangle(x1, y1, x2, y2, x3, y3, fillColor)
        }
        if hasStroke {
            strokeLine(x1, y1, x2, y2)
            strokeLine(x2, y2, x3, y3)
            strokeLine(x3, y3, x1, y1)
        }
    }

    /// 頂点位置の配列からポリゴンを描画します。凹多角形にも対応します。
    /// - Parameter points: ポリゴン頂点を定義する `(x, y)` タプルの配列。
    public func polygon(_ points: [(Float, Float)]) {
        guard points.count >= 3 else { return }

        if hasFill {
            let indices = EarClipTriangulator.triangulate(points)
            var i = 0
            while i + 2 < indices.count {
                addTriangle(
                    points[indices[i]].0, points[indices[i]].1,
                    points[indices[i + 1]].0, points[indices[i + 1]].1,
                    points[indices[i + 2]].0, points[indices[i + 2]].1,
                    fillColor
                )
                i += 3
            }
        }
        if hasStroke {
            for i in 0..<points.count {
                let next = (i + 1) % points.count
                strokeLine(points[i].0, points[i].1, points[next].0, points[next].1)
            }
        }
    }

    /// ラジアン単位の開始角・終了角で弧を描画します。
    /// - Parameters:
    ///   - x: 弧の中心のx座標。
    ///   - y: 弧の中心のy座標。
    ///   - w: 弧を囲む楕円の幅。
    ///   - h: 弧を囲む楕円の高さ。
    ///   - startAngle: 開始角（ラジアン）。
    ///   - stopAngle: 終了角（ラジアン）。
    ///   - mode: 弧の閉じ方モード（open、chord、または pie）。
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .open
    ) {
        let rx = w * 0.5
        let ry = h * 0.5
        let arcLength = stopAngle - startAngle
        let segments = max(4, Int(Float(ellipseSegments) * abs(arcLength) / (Float.pi * 2)))
        let step = arcLength / Float(segments)

        if hasFill {
            for i in 0..<segments {
                let a0 = startAngle + step * Float(i)
                let a1 = startAngle + step * Float(i + 1)
                let px0 = x + rx * cos(a0)
                let py0 = y + ry * sin(a0)
                let px1 = x + rx * cos(a1)
                let py1 = y + ry * sin(a1)
                addTriangle(x, y, px0, py0, px1, py1, fillColor)
            }
        }
        if hasStroke {
            for i in 0..<segments {
                let a0 = startAngle + step * Float(i)
                let a1 = startAngle + step * Float(i + 1)
                let px0 = x + rx * cos(a0)
                let py0 = y + ry * sin(a0)
                let px1 = x + rx * cos(a1)
                let py1 = y + ry * sin(a1)
                strokeLine(px0, py0, px1, py1)
            }
            let firstX = x + rx * cos(startAngle)
            let firstY = y + ry * sin(startAngle)
            let lastX = x + rx * cos(stopAngle)
            let lastY = y + ry * sin(stopAngle)
            switch mode {
            case .open:
                break
            case .chord:
                strokeLine(lastX, lastY, firstX, firstY)
            case .pie:
                strokeLine(firstX, firstY, x, y)
                strokeLine(x, y, lastX, lastY)
            }
        }
    }

    /// 2つのアンカーポイントと2つの制御点で定義される3次ベジェ曲線を描画します。
    /// - Parameters:
    ///   - x1: 第1アンカーポイントのx座標。
    ///   - y1: 第1アンカーポイントのy座標。
    ///   - cx1: 第1制御点のx座標。
    ///   - cy1: 第1制御点のy座標。
    ///   - cx2: 第2制御点のx座標。
    ///   - cy2: 第2制御点のy座標。
    ///   - x2: 第2アンカーポイントのx座標。
    ///   - y2: 第2アンカーポイントのy座標。
    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        let segments = 24
        let step = 1.0 / Float(segments)

        var prevX = x1
        var prevY = y1

        for i in 1...segments {
            let t = step * Float(i)
            let u = 1 - t
            let px = u * u * u * x1 + 3 * u * u * t * cx1 + 3 * u * t * t * cx2 + t * t * t * x2
            let py = u * u * u * y1 + 3 * u * u * t * cy1 + 3 * u * t * t * cy2 + t * t * t * y2

            if hasStroke {
                strokeLine(prevX, prevY, px, py)
            }

            prevX = px
            prevY = py
        }
    }

    /// 4点を通る Catmull-Rom スプライン曲線を描画します。
    ///
    /// 第2点から第3点の間に曲線が描画され、第1点と第4点は制御ハンドルとして使用されます。
    /// - Parameters:
    ///   - x1: 第1制御点のx座標。
    ///   - y1: 第1制御点のy座標。
    ///   - x2: 曲線開始点のx座標。
    ///   - y2: 曲線開始点のy座標。
    ///   - x3: 曲線終了点のx座標。
    ///   - y3: 曲線終了点のy座標。
    ///   - x4: 第2制御点のx座標。
    ///   - y4: 第2制御点のy座標。
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        guard hasStroke else { return }
        let segments = curveDetailCount
        var prevX = x2
        var prevY = y2

        for i in 1...segments {
            let t = Float(i) / Float(segments)
            let px = curvePoint(x1, x2, x3, x4, t)
            let py = curvePoint(y1, y2, y3, y4, t)
            strokeLine(prevX, prevY, px, py)
            prevX = px
            prevY = py
        }
    }

    /// 指定位置に小さな塗りつぶし円として点を描画します。
    /// - Parameters:
    ///   - x: 点のx座標。
    ///   - y: 点のy座標。
    public func point(_ x: Float, _ y: Float) {
        let r = currentStrokeWeight * 0.5
        let color = strokeColor
        // 三角形ファン円として描画（8セグメント = 24頂点）。
        // 一般的なポイントサイズでは真円と視覚的に区別がつかず、
        // ellipse/インスタンシングパスよりはるかに軽量です。
        let segments = 8
        let angleStep = Float.pi * 2.0 / Float(segments)
        var a0 = Float(0)
        for _ in 0..<segments {
            let a1 = a0 + angleStep
            addVertex(x, y, color)
            addVertex(x + r * cos(a0), y + r * sin(a0), color)
            addVertex(x + r * cos(a1), y + r * sin(a1), color)
            a0 = a1
        }
    }
}
