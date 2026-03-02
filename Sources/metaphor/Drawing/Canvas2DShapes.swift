import Metal
import simd

// MARK: - Shapes

extension Canvas2D {

    /// 矩形（座標解釈はrectModeに依存）
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
            addTriangle(rx, ry, rx + rw, ry, rx + rw, ry + rh, fillColor)
            addTriangle(rx, ry, rx + rw, ry + rh, rx, ry + rh, fillColor)
        }
        if hasStroke {
            strokePolyline([
                (rx, ry), (rx + rw, ry), (rx + rw, ry + rh), (rx, ry + rh)
            ], closed: true)
        }
    }

    /// 角丸矩形（均一コーナー半径）
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        rect(x, y, w, h, r, r, r, r)
    }

    /// 角丸矩形（コーナー別半径: tl=左上, tr=右上, br=右下, bl=左下）
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

    /// 矩形のショートカット（正方形）
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        rect(x, y, size, size)
    }

    /// 四辺形
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

    // MARK: - Gradient

    /// 線形グラデーション矩形を描画
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

    /// 放射状グラデーションを描画
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

    /// 楕円（座標解釈はellipseModeに依存）
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
        let step = Float.pi * 2.0 / Float(ellipseSegments)

        if hasFill {
            for i in 0..<ellipseSegments {
                let a0 = step * Float(i)
                let a1 = step * Float(i + 1)
                let px0 = cx + rx * cos(a0)
                let py0 = cy + ry * sin(a0)
                let px1 = cx + rx * cos(a1)
                let py1 = cy + ry * sin(a1)
                addTriangle(cx, cy, px0, py0, px1, py1, fillColor)
            }
        }
        if hasStroke {
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

    /// 円（ellipseの簡易版）
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        ellipse(x, y, diameter, diameter)
    }

    /// 直線
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        strokeLine(x1, y1, x2, y2)
    }

    /// 三角形
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

    /// 多角形（頂点配列）— 凹多角形対応
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

    /// 円弧 (startAngle, stopAngle はラジアン)
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

    /// 3次ベジェ曲線
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

    /// Catmull-Romスプライン曲線（4点: 制御点1, 開始点, 終了点, 制御点2）
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

    /// 点（小さい円として描画）
    public func point(_ x: Float, _ y: Float) {
        let r = currentStrokeWeight * 0.5
        let saved = (hasFill, fillColor, hasStroke)
        hasFill = true
        fillColor = strokeColor
        hasStroke = false
        ellipse(x, y, r * 2, r * 2)
        hasFill = saved.0
        fillColor = saved.1
        hasStroke = saved.2
    }
}
