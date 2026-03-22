extension SketchContext {

    // MARK: - 2D Shapes

    /// 矩形を描画します。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.rect(x, y, w, h)
    }

    /// 均一な角丸半径の角丸矩形を描画します。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///   - r: 角丸半径。
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        canvas.rect(x, y, w, h, r)
    }

    /// 各角に個別の角丸半径を持つ角丸矩形を描画します。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
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
        canvas.rect(x, y, w, h, tl, tr, br, bl)
    }

    /// リニアグラデーションで塗りつぶした矩形を描画します。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///   - c1: 開始色。
    ///   - c2: 終了色。
    ///   - axis: グラデーションの方向（デフォルト `.vertical`）。
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        canvas.linearGradient(x, y, w, h, c1, c2, axis: axis)
    }

    /// 放射状グラデーションを描画します。
    /// - Parameters:
    ///   - cx: 中心の x 座標。
    ///   - cy: 中心の y 座標。
    ///   - radius: グラデーションの半径。
    ///   - innerColor: 中心の色。
    ///   - outerColor: 外周の色。
    ///   - segments: セグメント数（デフォルト 36）。
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        canvas.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments)
    }

    /// 楕円を描画します。
    /// - Parameters:
    ///   - x: 中心の x 座標。
    ///   - y: 中心の y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.ellipse(x, y, w, h)
    }

    /// 円を描画します。
    /// - Parameters:
    ///   - x: 中心の x 座標。
    ///   - y: 中心の y 座標。
    ///   - diameter: 円の直径。
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        canvas.circle(x, y, diameter)
    }

    /// 正方形を描画します。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - size: 辺の長さ。
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        canvas.square(x, y, size)
    }

    /// 4つの頂点で定義される四角形を描画します。
    /// - Parameters:
    ///   - x1: 第1頂点の x 座標。
    ///   - y1: 第1頂点の y 座標。
    ///   - x2: 第2頂点の x 座標。
    ///   - y2: 第2頂点の y 座標。
    ///   - x3: 第3頂点の x 座標。
    ///   - y3: 第3頂点の y 座標。
    ///   - x4: 第4頂点の x 座標。
    ///   - y4: 第4頂点の y 座標。
    public func quad(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        canvas.quad(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// 2点間に線を描画します。
    /// - Parameters:
    ///   - x1: 始点の x 座標。
    ///   - y1: 始点の y 座標。
    ///   - x2: 終点の x 座標。
    ///   - y2: 終点の y 座標。
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        canvas.line(x1, y1, x2, y2)
    }

    /// 3つの頂点で定義される三角形を描画します。
    /// - Parameters:
    ///   - x1: 第1頂点の x 座標。
    ///   - y1: 第1頂点の y 座標。
    ///   - x2: 第2頂点の x 座標。
    ///   - y2: 第2頂点の y 座標。
    ///   - x3: 第3頂点の x 座標。
    ///   - y3: 第3頂点の y 座標。
    public func triangle(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float
    ) {
        canvas.triangle(x1, y1, x2, y2, x3, y3)
    }

    /// 座標タプルの配列からポリゴンを描画します。
    /// - Parameter points: (x, y) 座標タプルの配列。
    public func polygon(_ points: [(Float, Float)]) {
        canvas.polygon(points)
    }

    /// Vec2 ポイントの配列からポリゴンを描画します。
    /// - Parameter points: Vec2 ポイントの配列。
    public func polygon(_ points: [Vec2]) {
        canvas.polygon(points.map { ($0.x, $0.y) })
    }

    /// 円弧を描画します。
    /// - Parameters:
    ///   - x: 中心の x 座標。
    ///   - y: 中心の y 座標。
    ///   - w: 外接楕円の幅。
    ///   - h: 外接楕円の高さ。
    ///   - startAngle: ラジアン単位の開始角度。
    ///   - stopAngle: ラジアン単位の終了角度。
    ///   - mode: 円弧の描画モード（デフォルト `.open`）。
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .open
    ) {
        canvas.arc(x, y, w, h, startAngle, stopAngle, mode)
    }

    /// 3次ベジェ曲線を描画します。
    /// - Parameters:
    ///   - x1: 始点の x 座標。
    ///   - y1: 始点の y 座標。
    ///   - cx1: 第1制御点の x 座標。
    ///   - cy1: 第1制御点の y 座標。
    ///   - cx2: 第2制御点の x 座標。
    ///   - cy2: 第2制御点の y 座標。
    ///   - x2: 終点の x 座標。
    ///   - y2: 終点の y 座標。
    public func bezier(
        _ x1: Float, _ y1: Float,
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x2: Float, _ y2: Float
    ) {
        canvas.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
    }

    /// 単一の点を描画します。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func point(_ x: Float, _ y: Float) {
        canvas.point(x, y)
    }

    // MARK: - Custom Shapes (beginShape / endShape)

    /// 頂点ベースのカスタムシェイプの記録を開始します。
    /// - Parameter mode: シェイプの描画モード（デフォルト `.polygon`）。
    public func beginShape(_ mode: ShapeMode = .polygon) {
        canvas.beginShape(mode)
    }

    /// 現在のシェイプに頂点を追加します。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func vertex(_ x: Float, _ y: Float) {
        canvas.vertex(x, y)
    }

    /// 制御点と端点を持つ3次ベジェ頂点を追加します。
    /// - Parameters:
    ///   - cx1: 第1制御点の x 座標。
    ///   - cy1: 第1制御点の y 座標。
    ///   - cx2: 第2制御点の x 座標。
    ///   - cy2: 第2制御点の y 座標。
    ///   - x: 端点の x 座標。
    ///   - y: 端点の y 座標。
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        canvas.bezierVertex(cx1, cy1, cx2, cy2, x, y)
    }

    /// Catmull-Rom スプライン頂点を追加します。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func curveVertex(_ x: Float, _ y: Float) {
        canvas.curveVertex(x, y)
    }

    /// カーブセグメントの分割数を設定します。
    /// - Parameter n: 分割数。
    public func curveDetail(_ n: Int) {
        canvas.curveDetail(n)
    }

    /// Catmull-Rom カーブの張り具合を設定します。
    /// - Parameter t: 張り値。
    public func curveTightness(_ t: Float) {
        canvas.curveTightness(t)
    }

    /// 現在のシェイプ内にコンター（穴）の記録を開始します。
    public func beginContour() {
        canvas.beginContour()
    }

    /// 現在のコンター（穴）の記録を終了します。
    public func endContour() {
        canvas.endContour()
    }

    /// 頂点カラー付き頂点を追加します（2D）。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - color: 頂点カラー。
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        canvas.vertex(x, y, color)
    }

    /// UV テクスチャ座標付き頂点を追加します（2D）。
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - u: U テクスチャ座標。
    ///   - v: V テクスチャ座標。
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        canvas.vertex(x, y, u, v)
    }

    /// 現在のシェイプの記録を終了し描画します。
    /// - Parameter close: シェイプを閉じるかどうか（デフォルト `.open`）。
    public func endShape(_ close: CloseMode = .open) {
        canvas.endShape(close)
    }

    // MARK: - Clipping

    /// 以降の描画を指定した矩形にクリッピングします。
    ///
    /// - Parameters:
    ///   - x: クリップ領域の x 座標。
    ///   - y: クリップ領域の y 座標。
    ///   - w: クリップ領域の幅。
    ///   - h: クリップ領域の高さ。
    public func beginClip(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        canvas.beginClip(x, y, w, h)
    }

    /// 現在のクリップ領域を終了し、前の状態に復元します。
    public func endClip() {
        canvas.endClip()
    }
}
