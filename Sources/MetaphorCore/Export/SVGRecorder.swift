import Foundation
import simd

/// 2D 描画呼び出しを SVG ドキュメントとして記録します。
///
/// ``Canvas2D`` の図形メソッドがアクティブな recorder に幾何・スタイル・変換を
/// 通知し、``svgString()`` が決定論的な SVG テキストを生成します（数値は固定
/// フォーマット・属性順固定。同じ描画呼び出し列からは常に同じバイト列が出ます）。
///
/// ラスタライズと同じ API 呼び出しが入力のため、決定論レンダリング
/// （ADR-0002/0003）と同じ理由で出力はゴールデンファイル比較でテストできます。
@MainActor
final class SVGRecorder {

    /// 記録時点のスタイルと変換のスナップショット。
    struct Style {
        /// 塗り色（RGBA 0-1）。nil は `noFill()`
        var fill: SIMD4<Float>?
        /// 線色（RGBA 0-1）。nil は `noStroke()`
        var stroke: SIMD4<Float>?
        var strokeWeight: Float
        var strokeCap: StrokeCap
        var strokeJoin: StrokeJoin
        /// 記録時点の 2D 変換行列（SVG の transform 属性になる）
        var transform: float3x3
    }

    private struct Element {
        let tag: String
        /// 幾何属性（順序が出力順。決定論のため配列で保持）
        let attributes: [(String, String)]
        let style: Style
        /// 開いたパス等、fill を強制的に無効化する要素（line/polyline/points）
        let strokeOnly: Bool
        /// アクティブなクリップの ID（`<g clip-path>` で包む）。nil はクリップなし
        let clipID: Int?
    }

    private var elements: [Element] = []
    /// 背景色（`background()` の最後の呼び出し。それ以前の要素はクリアされる）
    private var backgroundColor: SIMD4<Float>?

    // クリップ管理
    private struct ClipRect {
        let id: Int
        let x: Float, y: Float, w: Float, h: Float
    }
    private var clipDefs: [ClipRect] = []
    private var clipStack: [Int] = []
    private var activeClipID: Int? { clipStack.last }

    // beginShape 状態
    private enum ShapeVertex {
        case vertex(Float, Float)
        case bezierVertex(Float, Float, Float, Float, Float, Float)
        case curveVertex(Float, Float)
    }
    private var shapeMode: ShapeMode?
    private var shapeVertices: [ShapeVertex] = []
    private var shapeContours: [[ShapeVertex]] = []
    private var inContour = false
    private var shapeStyle: Style?
    private var curveTightness: Float = 0

    /// 対応外機能の警告を機能名ごとに 1 回へ抑制する
    private var warnedFeatures: Set<String> = []

    /// 出力キャンバスサイズ
    let width: Float
    let height: Float

    /// `endSVGRecord()` が書き出す先のファイルパス
    let outputPath: String

    init(width: Float, height: Float, outputPath: String) {
        self.width = width
        self.height = height
        self.outputPath = outputPath
    }

    // MARK: - 図形の記録

    func recordBackground(_ color: SIMD4<Float>) {
        // 画面と同じ意味論: それまでの描画を消して全面を塗る
        elements.removeAll()
        backgroundColor = color
    }

    func recordRect(
        x: Float, y: Float, w: Float, h: Float,
        corners: (tl: Float, tr: Float, br: Float, bl: Float)? = nil,
        style: Style
    ) {
        if let corners {
            if corners.tl == corners.tr && corners.tr == corners.br && corners.br == corners.bl {
                // 均一角丸は rect の rx で表現
                append(Element(
                    tag: "rect",
                    attributes: [
                        ("x", fmt(x)), ("y", fmt(y)),
                        ("width", fmt(w)), ("height", fmt(h)),
                        ("rx", fmt(min(corners.tl, min(w, h) / 2))),
                    ],
                    style: style, strokeOnly: false, clipID: activeClipID))
            } else {
                // 個別角丸は path で構築
                append(Element(
                    tag: "path",
                    attributes: [("d", roundedRectPath(x: x, y: y, w: w, h: h, corners: corners))],
                    style: style, strokeOnly: false, clipID: activeClipID))
            }
        } else {
            append(Element(
                tag: "rect",
                attributes: [
                    ("x", fmt(x)), ("y", fmt(y)),
                    ("width", fmt(w)), ("height", fmt(h)),
                ],
                style: style, strokeOnly: false, clipID: activeClipID))
        }
    }

    func recordEllipse(cx: Float, cy: Float, rx: Float, ry: Float, style: Style) {
        append(Element(
            tag: "ellipse",
            attributes: [("cx", fmt(cx)), ("cy", fmt(cy)), ("rx", fmt(rx)), ("ry", fmt(ry))],
            style: style, strokeOnly: false, clipID: activeClipID))
    }

    func recordLine(x1: Float, y1: Float, x2: Float, y2: Float, style: Style) {
        append(Element(
            tag: "line",
            attributes: [("x1", fmt(x1)), ("y1", fmt(y1)), ("x2", fmt(x2)), ("y2", fmt(y2))],
            style: style, strokeOnly: true, clipID: activeClipID))
    }

    func recordPolygon(_ points: [(Float, Float)], closed: Bool, style: Style) {
        guard points.count >= 2 else { return }
        var d = "M" + point(points[0])
        for p in points.dropFirst() {
            d += "L" + point(p)
        }
        if closed { d += "Z" }
        append(Element(
            tag: "path", attributes: [("d", d)],
            style: style, strokeOnly: !closed, clipID: activeClipID))
    }

    func recordPoint(x: Float, y: Float, style: Style) {
        // Processing の point() はストローク色・ストローク幅の点
        guard let strokeColor = style.stroke else { return }
        var pointStyle = style
        pointStyle.fill = strokeColor
        pointStyle.stroke = nil
        append(Element(
            tag: "circle",
            attributes: [("cx", fmt(x)), ("cy", fmt(y)), ("r", fmt(max(style.strokeWeight / 2, 0.5)))],
            style: pointStyle, strokeOnly: false, clipID: activeClipID))
    }

    func recordArc(
        cx: Float, cy: Float, rx: Float, ry: Float,
        start: Float, stop: Float, mode: ArcMode, style: Style
    ) {
        let sweep = stop - start
        // 全周以上は楕円として出力
        if abs(sweep) >= Float.pi * 2 {
            recordEllipse(cx: cx, cy: cy, rx: rx, ry: ry, style: style)
            return
        }
        let sx = cx + rx * cos(start)
        let sy = cy + ry * sin(start)
        let ex = cx + rx * cos(stop)
        let ey = cy + ry * sin(stop)
        let largeArc = abs(sweep) > Float.pi ? "1" : "0"
        let sweepFlag = sweep > 0 ? "1" : "0"
        var d = "M\(fmt(sx)) \(fmt(sy))"
            + "A\(fmt(rx)) \(fmt(ry)) 0 \(largeArc) \(sweepFlag) \(fmt(ex)) \(fmt(ey))"
        var strokeOnly = false
        switch mode {
        case .pie, .default:
            d += "L" + point((cx, cy)) + "Z"
        case .chord:
            d += "Z"
        case .open:
            // fill は弦で閉じた形・stroke は開いた弧（Processing 互換）。
            // SVG では 1 要素で表現できないため、fill と stroke を分けて出力
            if style.fill != nil && style.stroke != nil {
                var fillStyle = style
                fillStyle.stroke = nil
                append(Element(
                    tag: "path", attributes: [("d", d + "Z")],
                    style: fillStyle, strokeOnly: false, clipID: activeClipID))
                var strokeStyle = style
                strokeStyle.fill = nil
                append(Element(
                    tag: "path", attributes: [("d", d)],
                    style: strokeStyle, strokeOnly: true, clipID: activeClipID))
                return
            }
            strokeOnly = style.fill == nil
            if style.fill != nil { d += "Z" }
        }
        append(Element(
            tag: "path", attributes: [("d", d)],
            style: style, strokeOnly: strokeOnly, clipID: activeClipID))
    }

    func recordBezier(
        x1: Float, y1: Float, cx1: Float, cy1: Float,
        cx2: Float, cy2: Float, x2: Float, y2: Float, style: Style
    ) {
        let d = "M\(fmt(x1)) \(fmt(y1))"
            + "C\(fmt(cx1)) \(fmt(cy1)) \(fmt(cx2)) \(fmt(cy2)) \(fmt(x2)) \(fmt(y2))"
        append(Element(
            tag: "path", attributes: [("d", d)],
            style: style, strokeOnly: true, clipID: activeClipID))
    }

    /// Catmull-Rom 曲線 1 区間（p1→p2、p0/p3 は制御点）を cubic bezier で出力します。
    func recordCurve(
        p0: (Float, Float), p1: (Float, Float), p2: (Float, Float), p3: (Float, Float),
        tightness: Float, style: Style
    ) {
        let d = "M\(fmt(p1.0)) \(fmt(p1.1))" + catmullRomSegment(p0: p0, p1: p1, p2: p2, p3: p3, tightness: tightness)
        append(Element(
            tag: "path", attributes: [("d", d)],
            style: style, strokeOnly: true, clipID: activeClipID))
    }

    // MARK: - beginShape / endShape

    func beginShape(_ mode: ShapeMode, style: Style, tightness: Float) {
        shapeMode = mode
        shapeVertices = []
        shapeContours = []
        inContour = false
        shapeStyle = style
        curveTightness = tightness
    }

    func vertex(_ x: Float, _ y: Float) {
        appendShapeVertex(.vertex(x, y))
    }

    func bezierVertex(_ cx1: Float, _ cy1: Float, _ cx2: Float, _ cy2: Float, _ x: Float, _ y: Float) {
        appendShapeVertex(.bezierVertex(cx1, cy1, cx2, cy2, x, y))
    }

    func curveVertex(_ x: Float, _ y: Float) {
        appendShapeVertex(.curveVertex(x, y))
    }

    func beginContour() {
        inContour = true
        shapeContours.append([])
    }

    func endContour() {
        inContour = false
    }

    private func appendShapeVertex(_ v: ShapeVertex) {
        if inContour {
            shapeContours[shapeContours.count - 1].append(v)
        } else {
            shapeVertices.append(v)
        }
    }

    func endShape(close: Bool) {
        defer {
            shapeMode = nil
            shapeVertices = []
            shapeContours = []
            shapeStyle = nil
        }
        guard let mode = shapeMode, let style = shapeStyle, !shapeVertices.isEmpty else { return }

        switch mode {
        case .polygon:
            var d = pathData(for: shapeVertices, close: close)
            for contour in shapeContours where !contour.isEmpty {
                d += pathData(for: contour, close: true)
            }
            var attributes: [(String, String)] = [("d", d)]
            if !shapeContours.isEmpty {
                attributes.append(("fill-rule", "evenodd"))
            }
            append(Element(
                tag: "path", attributes: attributes,
                style: style, strokeOnly: !close && shapeContours.isEmpty && style.fill == nil,
                clipID: activeClipID))
        case .points:
            for case .vertex(let x, let y) in shapeVertices {
                recordPoint(x: x, y: y, style: style)
            }
        case .lines:
            let xy = plainVertices()
            for i in stride(from: 0, to: xy.count - 1, by: 2) {
                recordLine(x1: xy[i].0, y1: xy[i].1, x2: xy[i + 1].0, y2: xy[i + 1].1, style: style)
            }
        case .triangles:
            let xy = plainVertices()
            for i in stride(from: 0, to: xy.count - 2, by: 3) {
                recordPolygon([xy[i], xy[i + 1], xy[i + 2]], closed: true, style: style)
            }
        case .triangleStrip:
            let xy = plainVertices()
            for i in 0..<(max(xy.count, 2) - 2) {
                recordPolygon([xy[i], xy[i + 1], xy[i + 2]], closed: true, style: style)
            }
        case .triangleFan:
            let xy = plainVertices()
            guard xy.count >= 3 else { return }
            for i in 1..<(xy.count - 1) {
                recordPolygon([xy[0], xy[i], xy[i + 1]], closed: true, style: style)
            }
        }
    }

    /// vertex のみの座標列（bezier/curve 頂点は特殊 mode では非対応のため無視）
    private func plainVertices() -> [(Float, Float)] {
        shapeVertices.compactMap {
            if case .vertex(let x, let y) = $0 { return (x, y) }
            return nil
        }
    }

    /// 頂点列（vertex / bezierVertex / curveVertex 混在）をパスデータへ変換します。
    private func pathData(for vertices: [ShapeVertex], close: Bool) -> String {
        // curveVertex は前後の点を制御点に使うため、連続区間をまとめて変換する
        var d = ""
        var curveRun: [(Float, Float)] = []
        var current: (Float, Float)?

        func flushCurveRun() {
            guard curveRun.count >= 2 else {
                // 曲線を張るには最低 4 点（両端制御点）が必要。足りない分は無視
                curveRun = []
                return
            }
            // Processing 互換: 先頭/末尾の点は制御点としてのみ使われる
            for i in 1..<(curveRun.count - 2 < 1 ? 1 : curveRun.count - 2) {
                let p0 = curveRun[max(0, i - 1)]
                let p1 = curveRun[i]
                let p2 = curveRun[i + 1]
                let p3 = curveRun[min(curveRun.count - 1, i + 2)]
                if current == nil || current! != p1 {
                    d += (d.isEmpty && current == nil ? "M" : "L") + point(p1)
                }
                d += catmullRomSegment(p0: p0, p1: p1, p2: p2, p3: p3, tightness: curveTightness)
                current = p2
            }
            curveRun = []
        }

        for v in vertices {
            switch v {
            case .vertex(let x, let y):
                flushCurveRun()
                d += (current == nil ? "M" : "L") + point((x, y))
                current = (x, y)
            case .bezierVertex(let cx1, let cy1, let cx2, let cy2, let x, let y):
                flushCurveRun()
                // bezierVertex は直前の頂点が必要（無ければ M で開始）
                if current == nil {
                    d += "M" + point((x, y))
                } else {
                    d += "C\(fmt(cx1)) \(fmt(cy1)) \(fmt(cx2)) \(fmt(cy2)) \(fmt(x)) \(fmt(y))"
                }
                current = (x, y)
            case .curveVertex(let x, let y):
                curveRun.append((x, y))
            }
        }
        flushCurveRun()
        if close && !d.isEmpty { d += "Z" }
        return d
    }

    /// Catmull-Rom 区間 p1→p2 を SVG の C コマンドへ変換します。
    private func catmullRomSegment(
        p0: (Float, Float), p1: (Float, Float), p2: (Float, Float), p3: (Float, Float),
        tightness: Float
    ) -> String {
        // Processing の curveTightness s を反映した接線スケール
        let s = (1 - tightness) / 6
        let c1 = (p1.0 + (p2.0 - p0.0) * s, p1.1 + (p2.1 - p0.1) * s)
        let c2 = (p2.0 - (p3.0 - p1.0) * s, p2.1 - (p3.1 - p1.1) * s)
        return "C\(fmt(c1.0)) \(fmt(c1.1)) \(fmt(c2.0)) \(fmt(c2.1)) \(fmt(p2.0)) \(fmt(p2.1))"
    }

    // MARK: - クリップ

    func beginClip(x: Float, y: Float, w: Float, h: Float) {
        let clip = ClipRect(id: clipDefs.count + 1, x: x, y: y, w: w, h: h)
        clipDefs.append(clip)
        clipStack.append(clip.id)
    }

    func endClip() {
        _ = clipStack.popLast()
    }

    // MARK: - 対応外

    /// 対応外機能を警告します（機能名ごとに 1 回のみ）。
    func recordUnsupported(_ feature: String) {
        guard !warnedFeatures.contains(feature) else { return }
        warnedFeatures.insert(feature)
        metaphorWarning("SVG export: \(feature) is not supported and was skipped")
    }

    // MARK: - SVG 生成

    /// 記録内容から SVG ドキュメントを生成します（決定論的出力）。
    func svgString() -> String {
        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(
            #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(fmt(width))" height="\#(fmt(height))" viewBox="0 0 \#(fmt(width)) \#(fmt(height))">"#
        )
        if !clipDefs.isEmpty {
            lines.append("<defs>")
            for clip in clipDefs {
                lines.append(
                    #"<clipPath id="clip\#(clip.id)"><rect x="\#(fmt(clip.x))" y="\#(fmt(clip.y))" width="\#(fmt(clip.w))" height="\#(fmt(clip.h))"/></clipPath>"#
                )
            }
            lines.append("</defs>")
        }
        if let bg = backgroundColor {
            lines.append(
                #"<rect width="\#(fmt(width))" height="\#(fmt(height))" fill="\#(rgb(bg))"\#(opacityAttr("fill-opacity", bg))/>"#
            )
        }
        for element in elements {
            var attrs = ""
            for (key, value) in element.attributes {
                attrs += " \(key)=\"\(value)\""
            }
            attrs += styleAttributes(element.style, strokeOnly: element.strokeOnly)
            var line = "<\(element.tag)\(attrs)/>"
            if let clipID = element.clipID {
                line = #"<g clip-path="url(#clip\#(clipID))">"# + line + "</g>"
            }
            lines.append(line)
        }
        lines.append("</svg>")
        return lines.map { $0 + "\n" }.joined()
    }

    private func append(_ element: Element) {
        elements.append(element)
    }

    // MARK: - 属性フォーマット

    private func styleAttributes(_ style: Style, strokeOnly: Bool) -> String {
        var out = ""
        if strokeOnly || style.fill == nil {
            out += #" fill="none""#
        } else if let fill = style.fill {
            out += #" fill="\#(rgb(fill))""# + opacityAttr("fill-opacity", fill)
        }
        if let stroke = style.stroke {
            out += #" stroke="\#(rgb(stroke))""# + opacityAttr("stroke-opacity", stroke)
            out += #" stroke-width="\#(fmt(style.strokeWeight))""#
            if style.strokeCap != .butt {
                out += #" stroke-linecap="\#(style.strokeCap == .round ? "round" : "square")""#
            }
            if style.strokeJoin != .miter {
                out += #" stroke-linejoin="\#(style.strokeJoin == .round ? "round" : "bevel")""#
            }
        }
        out += transformAttr(style.transform)
        return out
    }

    private func transformAttr(_ m: float3x3) -> String {
        // 列優先 float3x3 → SVG matrix(a b c d e f)
        let (a, b) = (m.columns.0.x, m.columns.0.y)
        let (c, d) = (m.columns.1.x, m.columns.1.y)
        let (e, f) = (m.columns.2.x, m.columns.2.y)
        if a == 1, b == 0, c == 0, d == 1, e == 0, f == 0 { return "" }
        return #" transform="matrix(\#(fmt(a)) \#(fmt(b)) \#(fmt(c)) \#(fmt(d)) \#(fmt(e)) \#(fmt(f)))""#
    }

    private func rgb(_ color: SIMD4<Float>) -> String {
        let r = Int((min(max(color.x, 0), 1) * 255).rounded())
        let g = Int((min(max(color.y, 0), 1) * 255).rounded())
        let b = Int((min(max(color.z, 0), 1) * 255).rounded())
        return "rgb(\(r),\(g),\(b))"
    }

    private func opacityAttr(_ name: String, _ color: SIMD4<Float>) -> String {
        color.w >= 1 ? "" : #" \#(name)="\#(fmt(color.w))""#
    }

    private func point(_ p: (Float, Float)) -> String {
        "\(fmt(p.0)) \(fmt(p.1))"
    }

    /// 決定論的な数値フォーマット（小数 3 桁・末尾ゼロ除去）。
    private func fmt(_ value: Float) -> String {
        var s = String(format: "%.3f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        // "-0" を "0" へ正規化
        return s == "-0" ? "0" : s
    }

    private func roundedRectPath(
        x: Float, y: Float, w: Float, h: Float,
        corners: (tl: Float, tr: Float, br: Float, bl: Float)
    ) -> String {
        let maxR = min(w, h) / 2
        let tl = min(corners.tl, maxR), tr = min(corners.tr, maxR)
        let br = min(corners.br, maxR), bl = min(corners.bl, maxR)
        var d = "M\(fmt(x + tl)) \(fmt(y))"
        d += "L\(fmt(x + w - tr)) \(fmt(y))"
        if tr > 0 { d += "A\(fmt(tr)) \(fmt(tr)) 0 0 1 \(fmt(x + w)) \(fmt(y + tr))" }
        d += "L\(fmt(x + w)) \(fmt(y + h - br))"
        if br > 0 { d += "A\(fmt(br)) \(fmt(br)) 0 0 1 \(fmt(x + w - br)) \(fmt(y + h))" }
        d += "L\(fmt(x + bl)) \(fmt(y + h))"
        if bl > 0 { d += "A\(fmt(bl)) \(fmt(bl)) 0 0 1 \(fmt(x)) \(fmt(y + h - bl))" }
        d += "L\(fmt(x)) \(fmt(y + tl))"
        if tl > 0 { d += "A\(fmt(tl)) \(fmt(tl)) 0 0 1 \(fmt(x + tl)) \(fmt(y))" }
        d += "Z"
        return d
    }
}
