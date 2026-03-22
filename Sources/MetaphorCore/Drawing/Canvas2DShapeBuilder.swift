import Metal
import simd

// MARK: - カスタムシェイプ (beginShape / endShape)

extension Canvas2D {

    /// カスタムシェイプの頂点記録を開始します。
    /// - Parameter mode: シェイプモード（polygon、triangles など）。
    public func beginShape(_ mode: ShapeMode = .polygon) {
        isRecordingShape = true
        shapeMode = mode
        shapeVertexList.removeAll(keepingCapacity: true)
        contourVertices.removeAll(keepingCapacity: true)
        isRecordingContour = false
    }

    /// 現在のシェイプに頂点を追加します（beginShape と endShape の間で使用）。
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    public func vertex(_ x: Float, _ y: Float) {
        guard isRecordingShape else { return }
        if isRecordingContour {
            currentContour.append((x, y))
        } else {
            shapeVertexList.append(.normal(x, y))
        }
    }

    /// 頂点カラー付きの頂点を追加します。
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    ///   - color: 頂点カラー。
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        guard isRecordingShape else { return }
        shapeVertexList.append(.colored(x, y, color.simd))
    }

    /// テクスチャマッピング用のUV座標付き頂点を追加します。
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    ///   - u: 水平テクスチャ座標。
    ///   - v: 垂直テクスチャ座標。
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        guard isRecordingShape else { return }
        shapeVertexList.append(.textured(x, y, u, v))
    }

    /// 3次ベジェ曲線の制御点と終点を追加します（beginShape と endShape の間で使用）。
    /// - Parameters:
    ///   - cx1: 第1制御点のx座標。
    ///   - cy1: 第1制御点のy座標。
    ///   - cx2: 第2制御点のx座標。
    ///   - cy2: 第2制御点のy座標。
    ///   - x: 終点のx座標。
    ///   - y: 終点のy座標。
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        guard isRecordingShape else { return }
        shapeVertexList.append(.bezier(cx1: cx1, cy1: cy1, cx2: cx2, cy2: cy2, x: x, y: y))
    }

    /// Catmull-Rom スプライン頂点を追加します（beginShape と endShape の間で使用）。
    /// - Parameters:
    ///   - x: x座標。
    ///   - y: y座標。
    public func curveVertex(_ x: Float, _ y: Float) {
        guard isRecordingShape else { return }
        shapeVertexList.append(.curve(x, y))
    }

    /// 現在のシェイプ内のコンター（穴）の記録を開始します（beginShape と endShape の間で使用）。
    public func beginContour() {
        guard isRecordingShape else { return }
        isRecordingContour = true
        currentContour.removeAll(keepingCapacity: true)
    }

    /// 現在のコンター（穴）の記録を終了します。
    public func endContour() {
        guard isRecordingContour else { return }
        isRecordingContour = false
        if currentContour.count >= 3 {
            contourVertices.append(currentContour)
        }
    }

    /// 曲線の近似に使用するセグメント数を設定します。
    /// - Parameter n: セグメント数（最小1）。
    public func curveDetail(_ n: Int) {
        curveDetailCount = max(1, n)
    }

    /// 曲線のタイトネスを設定します（-5.0 から 5.0; 0.0 が標準 Catmull-Rom）。
    /// - Parameter t: タイトネス値。
    public func curveTightness(_ t: Float) {
        curveTightnessValue = t
    }

    /// シェイプ記録を終了し、記録された頂点をテッセレーション・描画します。
    /// - Parameter close: シェイプを閉じるかどうか。
    public func endShape(_ close: CloseMode = .open) {
        guard isRecordingShape else { return }
        isRecordingShape = false

        guard !shapeVertexList.isEmpty else { return }

        let hasPerVertexColor = shapeVertexList.contains { if case .colored = $0 { return true }; return false }
        let hasUV = shapeVertexList.contains { if case .textured = $0 { return true }; return false }

        if hasPerVertexColor || hasUV {
            let exVerts = expandShapeVerticesEx()
            guard !exVerts.isEmpty else { return }

            switch shapeMode {
            case .polygon:
                drawPolygonShapeEx(exVerts, close: close)
            case .triangles:
                drawTrianglesShapeEx(exVerts)
            case .triangleStrip:
                drawTriangleStripShapeEx(exVerts)
            case .triangleFan:
                drawTriangleFanShapeEx(exVerts)
            case .points:
                drawPointsShape(exVerts.map { $0.tuple })
            case .lines:
                drawLinesShape(exVerts.map { $0.tuple })
            }
        } else {
            let verts = expandShapeVerticesEx().map { $0.tuple }
            guard !verts.isEmpty else { return }

            switch shapeMode {
            case .polygon:
                drawPolygonShape(verts, close: close)
            case .points:
                drawPointsShape(verts)
            case .lines:
                drawLinesShape(verts)
            case .triangles:
                drawTrianglesShape(verts)
            case .triangleStrip:
                drawTriangleStripShape(verts)
            case .triangleFan:
                drawTriangleFanShape(verts)
            }
        }
    }

    /// 位置とオプションの頂点カラー・UV座標を持つ展開済み頂点。
    struct ExpandedVertex {
        var x: Float
        var y: Float
        var color: SIMD4<Float>?
        var u: Float?
        var v: Float?

        var tuple: (Float, Float) { (x, y) }
    }

    /// 記録された ShapeVertexType 配列を ExpandedVertex 配列に展開します。
    func expandShapeVerticesEx() -> [ExpandedVertex] {
        var result: [ExpandedVertex] = []
        result.reserveCapacity(shapeVertexList.count * 4)

        var hasCurves = false
        var hasBeziers = false

        for v in shapeVertexList {
            switch v {
            case .curve: hasCurves = true
            case .bezier: hasBeziers = true
            default: break
            }
        }

        if !hasCurves && !hasBeziers {
            for v in shapeVertexList {
                switch v {
                case .normal(let x, let y):
                    result.append(ExpandedVertex(x: x, y: y))
                case .colored(let x, let y, let c):
                    result.append(ExpandedVertex(x: x, y: y, color: c))
                case .textured(let x, let y, let u, let v):
                    result.append(ExpandedVertex(x: x, y: y, u: u, v: v))
                default: break
                }
            }
            return result
        }

        if hasCurves {
            var curvePoints: [(Float, Float)] = []
            for v in shapeVertexList {
                if case .curve(let x, let y) = v {
                    curvePoints.append((x, y))
                }
            }
            if curvePoints.count >= 4 {
                let s = (1 - curveTightnessValue) / 2
                for i in 1..<(curvePoints.count - 2) {
                    let p0 = curvePoints[i - 1]
                    let p1 = curvePoints[i]
                    let p2 = curvePoints[i + 1]
                    let p3 = curvePoints[i + 2]
                    if i == 1 { result.append(ExpandedVertex(x: p1.0, y: p1.1)) }
                    for step in 1...curveDetailCount {
                        let t = Float(step) / Float(curveDetailCount)
                        let t2 = t * t
                        let t3 = t2 * t
                        let x = s * ((-p0.0 + 3 * p1.0 - 3 * p2.0 + p3.0) * t3
                                    + (2 * p0.0 - 5 * p1.0 + 4 * p2.0 - p3.0) * t2
                                    + (-p0.0 + p2.0) * t
                                    + 2 * p1.0) / 1.0
                            + (1 - s) * curvePointLinear(p1.0, p2.0, t)
                        let y = s * ((-p0.1 + 3 * p1.1 - 3 * p2.1 + p3.1) * t3
                                    + (2 * p0.1 - 5 * p1.1 + 4 * p2.1 - p3.1) * t2
                                    + (-p0.1 + p2.1) * t
                                    + 2 * p1.1) / 1.0
                            + (1 - s) * curvePointLinear(p1.1, p2.1, t)
                        result.append(ExpandedVertex(x: x, y: y))
                    }
                }
            }
            return result
        }

        var lastX: Float = 0, lastY: Float = 0
        for v in shapeVertexList {
            switch v {
            case .normal(let x, let y):
                result.append(ExpandedVertex(x: x, y: y))
                lastX = x; lastY = y
            case .colored(let x, let y, let c):
                result.append(ExpandedVertex(x: x, y: y, color: c))
                lastX = x; lastY = y
            case .textured(let x, let y, let u, let v):
                result.append(ExpandedVertex(x: x, y: y, u: u, v: v))
                lastX = x; lastY = y
            case .bezier(let cx1, let cy1, let cx2, let cy2, let x, let y):
                let segments = curveDetailCount
                for step in 1...segments {
                    let t = Float(step) / Float(segments)
                    let px = bezierPoint(lastX, cx1, cx2, x, t)
                    let py = bezierPoint(lastY, cy1, cy2, y, t)
                    result.append(ExpandedVertex(x: px, y: py))
                }
                lastX = x; lastY = y
            case .curve:
                break
            }
        }
        return result
    }

    private func curvePointLinear(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    // MARK: - プライベート: シェイプテッセレーション

    func drawPolygonShape(_ verts: [(Float, Float)], close: CloseMode) {
        if hasFill && verts.count >= 3 {
            if contourVertices.isEmpty {
                let indices = EarClipTriangulator.triangulate(verts)
                var i = 0
                while i + 2 < indices.count {
                    addTriangle(
                        verts[indices[i]].0, verts[indices[i]].1,
                        verts[indices[i + 1]].0, verts[indices[i + 1]].1,
                        verts[indices[i + 2]].0, verts[indices[i + 2]].1,
                        fillColor
                    )
                    i += 3
                }
            } else {
                let (merged, indices) = EarClipTriangulator.triangulateWithHoles(
                    outer: verts,
                    holes: contourVertices
                )
                var i = 0
                while i + 2 < indices.count {
                    addTriangle(
                        merged[indices[i]].0, merged[indices[i]].1,
                        merged[indices[i + 1]].0, merged[indices[i + 1]].1,
                        merged[indices[i + 2]].0, merged[indices[i + 2]].1,
                        fillColor
                    )
                    i += 3
                }
            }
        }

        if hasStroke && verts.count >= 2 {
            strokePolyline(verts, closed: close == .close)
        }
    }

    func drawPointsShape(_ verts: [(Float, Float)]) {
        for v in verts {
            point(v.0, v.1)
        }
    }

    func drawLinesShape(_ verts: [(Float, Float)]) {
        guard hasStroke else { return }
        var i = 0
        while i + 1 < verts.count {
            strokeLine(verts[i].0, verts[i].1, verts[i + 1].0, verts[i + 1].1)
            i += 2
        }
    }

    func drawTrianglesShape(_ verts: [(Float, Float)]) {
        var i = 0
        while i + 2 < verts.count {
            if hasFill {
                addTriangle(
                    verts[i].0, verts[i].1,
                    verts[i + 1].0, verts[i + 1].1,
                    verts[i + 2].0, verts[i + 2].1,
                    fillColor
                )
            }
            if hasStroke {
                strokeLine(verts[i].0, verts[i].1, verts[i + 1].0, verts[i + 1].1)
                strokeLine(verts[i + 1].0, verts[i + 1].1, verts[i + 2].0, verts[i + 2].1)
                strokeLine(verts[i + 2].0, verts[i + 2].1, verts[i].0, verts[i].1)
            }
            i += 3
        }
    }

    func drawTriangleStripShape(_ verts: [(Float, Float)]) {
        guard verts.count >= 3 else { return }
        for i in 0..<(verts.count - 2) {
            let (a, b, c) = i % 2 == 0
                ? (verts[i], verts[i + 1], verts[i + 2])
                : (verts[i + 1], verts[i], verts[i + 2])

            if hasFill {
                addTriangle(a.0, a.1, b.0, b.1, c.0, c.1, fillColor)
            }
            if hasStroke {
                strokeLine(a.0, a.1, b.0, b.1)
                strokeLine(b.0, b.1, c.0, c.1)
                strokeLine(c.0, c.1, a.0, a.1)
            }
        }
    }

    func drawTriangleFanShape(_ verts: [(Float, Float)]) {
        guard verts.count >= 3 else { return }
        for i in 1..<(verts.count - 1) {
            if hasFill {
                addTriangle(
                    verts[0].0, verts[0].1,
                    verts[i].0, verts[i].1,
                    verts[i + 1].0, verts[i + 1].1,
                    fillColor
                )
            }
            if hasStroke {
                strokeLine(verts[0].0, verts[0].1, verts[i].0, verts[i].1)
                strokeLine(verts[i].0, verts[i].1, verts[i + 1].0, verts[i + 1].1)
            }
        }
        if hasStroke && verts.count >= 3 {
            strokeLine(verts[verts.count - 1].0, verts[verts.count - 1].1, verts[0].0, verts[0].1)
        }
    }

    // MARK: - プライベート: 頂点カラー付きシェイプ描画

    func drawPolygonShapeEx(_ verts: [ExpandedVertex], close: CloseMode) {
        if hasFill && verts.count >= 3 {
            let tuples = verts.map { $0.tuple }
            let indices = EarClipTriangulator.triangulate(tuples)
            var i = 0
            while i + 2 < indices.count {
                let v0 = verts[indices[i]]
                let v1 = verts[indices[i + 1]]
                let v2 = verts[indices[i + 2]]
                addVertex(v0.x, v0.y, v0.color ?? fillColor)
                addVertex(v1.x, v1.y, v1.color ?? fillColor)
                addVertex(v2.x, v2.y, v2.color ?? fillColor)
                i += 3
            }
        }
        if hasStroke && verts.count >= 2 {
            strokePolyline(verts.map { $0.tuple }, closed: close == .close)
        }
    }

    func drawTrianglesShapeEx(_ verts: [ExpandedVertex]) {
        var i = 0
        while i + 2 < verts.count {
            if hasFill {
                addVertex(verts[i].x, verts[i].y, verts[i].color ?? fillColor)
                addVertex(verts[i+1].x, verts[i+1].y, verts[i+1].color ?? fillColor)
                addVertex(verts[i+2].x, verts[i+2].y, verts[i+2].color ?? fillColor)
            }
            if hasStroke {
                strokeLine(verts[i].x, verts[i].y, verts[i+1].x, verts[i+1].y)
                strokeLine(verts[i+1].x, verts[i+1].y, verts[i+2].x, verts[i+2].y)
                strokeLine(verts[i+2].x, verts[i+2].y, verts[i].x, verts[i].y)
            }
            i += 3
        }
    }

    func drawTriangleStripShapeEx(_ verts: [ExpandedVertex]) {
        guard verts.count >= 3 else { return }
        for i in 0..<(verts.count - 2) {
            let (a, b, c) = i % 2 == 0
                ? (verts[i], verts[i + 1], verts[i + 2])
                : (verts[i + 1], verts[i], verts[i + 2])
            if hasFill {
                addVertex(a.x, a.y, a.color ?? fillColor)
                addVertex(b.x, b.y, b.color ?? fillColor)
                addVertex(c.x, c.y, c.color ?? fillColor)
            }
            if hasStroke {
                strokeLine(a.x, a.y, b.x, b.y)
                strokeLine(b.x, b.y, c.x, c.y)
                strokeLine(c.x, c.y, a.x, a.y)
            }
        }
    }

    func drawTriangleFanShapeEx(_ verts: [ExpandedVertex]) {
        guard verts.count >= 3 else { return }
        for i in 1..<(verts.count - 1) {
            if hasFill {
                addVertex(verts[0].x, verts[0].y, verts[0].color ?? fillColor)
                addVertex(verts[i].x, verts[i].y, verts[i].color ?? fillColor)
                addVertex(verts[i+1].x, verts[i+1].y, verts[i+1].color ?? fillColor)
            }
            if hasStroke {
                strokeLine(verts[0].x, verts[0].y, verts[i].x, verts[i].y)
                strokeLine(verts[i].x, verts[i].y, verts[i+1].x, verts[i+1].y)
            }
        }
        if hasStroke && verts.count >= 3 {
            strokeLine(verts[verts.count - 1].x, verts[verts.count - 1].y, verts[0].x, verts[0].y)
        }
    }
}
