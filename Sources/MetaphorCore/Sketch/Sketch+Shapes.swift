// MARK: - 2D Transform & Shapes

extension Sketch {

    // MARK: 2D Transform Stack

    /// 現在の変換とスタイル状態をスタックに保存します。
    public func push() {
        context.push()
    }

    /// 最後に保存された変換とスタイル状態をスタックから復元します。
    public func pop() {
        context.pop()
    }

    /// 現在のスタイル状態（fill、stroke など）をスタックに保存します。
    public func pushStyle() {
        context.pushStyle()
    }

    /// 最後に保存されたスタイル状態をスタックから復元します。
    public func popStyle() {
        context.popStyle()
    }

    /// 現在の変換に 2D 平行移動を適用します。
    ///
    /// - Parameters:
    ///   - x: 水平方向の移動量。
    ///   - y: 垂直方向の移動量。
    public func translate(_ x: Float, _ y: Float) {
        context.translate(x, y)
    }

    /// 現在の変換に 2D 回転を適用します。
    ///
    /// - Parameter angle: ラジアン単位の回転角度。
    public func rotate(_ angle: Float) {
        context.rotate(angle)
    }

    /// 現在の変換に非均一 2D スケールを適用します。
    ///
    /// - Parameters:
    ///   - sx: 水平方向のスケール係数。
    ///   - sy: 垂直方向のスケール係数。
    public func scale(_ sx: Float, _ sy: Float) {
        context.scale(sx, sy)
    }

    /// 現在の変換に均一 2D スケールを適用します。
    ///
    /// - Parameter s: 均一スケール係数。
    public func scale(_ s: Float) {
        context.scale(s)
    }

    // MARK: 2D Shapes

    /// 矩形を描画します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.rect(x, y, w, h)
    }

    /// 均一な角丸半径の角丸矩形を描画します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///   - r: 角丸半径。
    public func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ r: Float) {
        context.rect(x, y, w, h, r)
    }

    /// 各角に個別の角丸半径を持つ角丸矩形を描画します。
    ///
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
        context.rect(x, y, w, h, tl, tr, br, bl)
    }

    /// リニアグラデーション矩形を描画します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅。
    ///   - h: 高さ。
    ///   - c1: 開始色。
    ///   - c2: 終了色。
    ///   - axis: グラデーションの方向。
    public func linearGradient(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float,
        _ c1: Color, _ c2: Color, axis: GradientAxis = .vertical
    ) {
        context.linearGradient(x, y, w, h, c1, c2, axis: axis)
    }

    /// 放射状グラデーション円を描画します。
    ///
    /// - Parameters:
    ///   - cx: 中心の x 座標。
    ///   - cy: 中心の y 座標。
    ///   - radius: 外側の半径。
    ///   - innerColor: 中心の色。
    ///   - outerColor: 外周の色。
    ///   - segments: 滑らかさのためのセグメント数。
    public func radialGradient(
        _ cx: Float, _ cy: Float, _ radius: Float,
        _ innerColor: Color, _ outerColor: Color,
        segments: Int = 36
    ) {
        context.radialGradient(cx, cy, radius, innerColor, outerColor, segments: segments)
    }

    /// 楕円を描画します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - w: 幅（水平方向の直径）。
    ///   - h: 高さ（垂直方向の直径）。
    public func ellipse(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        context.ellipse(x, y, w, h)
    }

    /// 円を描画します。
    ///
    /// - Parameters:
    ///   - x: 中心の x 座標。
    ///   - y: 中心の y 座標。
    ///   - diameter: 円の直径。
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        context.circle(x, y, diameter)
    }

    /// 正方形を描画します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - size: 辺の長さ。
    public func square(_ x: Float, _ y: Float, _ size: Float) {
        context.square(x, y, size)
    }

    /// 4つの頂点で定義される四角形を描画します。
    ///
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
        context.quad(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// 2点間に線を描画します。
    ///
    /// - Parameters:
    ///   - x1: 始点の x 座標。
    ///   - y1: 始点の y 座標。
    ///   - x2: 終点の x 座標。
    ///   - y2: 終点の y 座標。
    public func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        context.line(x1, y1, x2, y2)
    }

    /// 3つの頂点で定義される三角形を描画します。
    ///
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
        context.triangle(x1, y1, x2, y2, x3, y3)
    }

    /// 座標タプルの配列からポリゴンを描画します。
    ///
    /// - Parameter points: `(x, y)` タプルとしてのポリゴン頂点。
    public func polygon(_ points: [(Float, Float)]) {
        context.polygon(points)
    }

    /// ``Vec2`` 配列からポリゴンを描画します。
    ///
    /// - Parameter points: ポリゴン頂点。
    public func polygon(_ points: [Vec2]) {
        context.polygon(points)
    }

    /// 円弧を描画します。
    ///
    /// - Parameters:
    ///   - x: 円弧の中心の x 座標。
    ///   - y: 円弧の中心の y 座標。
    ///   - w: 円弧の外接楕円の幅。
    ///   - h: 円弧の外接楕円の高さ。
    ///   - startAngle: ラジアン単位の開始角度。
    ///   - stopAngle: ラジアン単位の終了角度。
    ///   - mode: 円弧の描画モード。
    public func arc(
        _ x: Float, _ y: Float,
        _ w: Float, _ h: Float,
        _ startAngle: Float, _ stopAngle: Float,
        _ mode: ArcMode = .open
    ) {
        context.arc(x, y, w, h, startAngle, stopAngle, mode)
    }

    /// 3次ベジェ曲線を描画します。
    ///
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
        context.bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)
    }

    /// 単一の点を描画します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func point(_ x: Float, _ y: Float) {
        context.point(x, y)
    }

    // MARK: Custom Shapes (beginShape / endShape)

    /// カスタムシェイプの頂点記録を開始します。
    ///
    /// - Parameter mode: シェイプモード（例: polygon、triangles、lines）。
    public func beginShape(_ mode: ShapeMode = .polygon) {
        context.beginShape(mode)
    }

    /// 現在のシェイプに 2D 頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func vertex(_ x: Float, _ y: Float) {
        context.vertex(x, y)
    }

    /// 現在のシェイプに頂点カラー付き 2D 頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - color: 頂点カラー。
    public func vertex(_ x: Float, _ y: Float, _ color: Color) {
        context.vertex(x, y, color)
    }

    /// 現在のシェイプにテクスチャ座標付き 2D 頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    ///   - u: 水平テクスチャ座標。
    ///   - v: 垂直テクスチャ座標。
    public func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) {
        context.vertex(x, y, u, v)
    }

    /// 現在のシェイプに3次ベジェ頂点を追加します。
    ///
    /// - Parameters:
    ///   - cx1: 第1制御点の x 座標。
    ///   - cy1: 第1制御点の y 座標。
    ///   - cx2: 第2制御点の x 座標。
    ///   - cy2: 第2制御点の y 座標。
    ///   - x: アンカーポイントの x 座標。
    ///   - y: アンカーポイントの y 座標。
    public func bezierVertex(
        _ cx1: Float, _ cy1: Float,
        _ cx2: Float, _ cy2: Float,
        _ x: Float, _ y: Float
    ) {
        context.bezierVertex(cx1, cy1, cx2, cy2, x, y)
    }

    /// 現在のシェイプに Catmull-Rom スプライン頂点を追加します。
    ///
    /// - Parameters:
    ///   - x: x 座標。
    ///   - y: y 座標。
    public func curveVertex(_ x: Float, _ y: Float) {
        context.curveVertex(x, y)
    }

    /// カーブ補間のセグメント数を設定します。
    ///
    /// - Parameter n: カーブの詳細度。
    public func curveDetail(_ n: Int) {
        context.curveDetail(n)
    }

    /// Catmull-Rom スプラインカーブの張り具合を設定します。
    ///
    /// - Parameter t: 張り値（0 = デフォルト、1 = 直線）。
    public func curveTightness(_ t: Float) {
        context.curveTightness(t)
    }

    /// 現在のシェイプ内にコンター（穴）の定義を開始します。
    public func beginContour() {
        context.beginContour()
    }

    /// 現在のコンター定義を終了します。
    public func endContour() {
        context.endContour()
    }

    /// 4点を通る Catmull-Rom スプラインカーブを描画します。
    ///
    /// - Parameters:
    ///   - x1: 第1制御点の x 座標。
    ///   - y1: 第1制御点の y 座標。
    ///   - x2: 始点の x 座標。
    ///   - y2: 始点の y 座標。
    ///   - x3: 終点の x 座標。
    ///   - y3: 終点の y 座標。
    ///   - x4: 第2制御点の x 座標。
    ///   - y4: 第2制御点の y 座標。
    public func curve(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ x3: Float, _ y3: Float,
        _ x4: Float, _ y4: Float
    ) {
        context.curve(x1, y1, x2, y2, x3, y3, x4, y4)
    }

    /// 現在のシェイプの記録を終了し描画します。
    ///
    /// - Parameter close: 最後の頂点と最初の頂点を接続してシェイプを閉じるかどうか。
    public func endShape(_ close: CloseMode = .open) {
        context.endShape(close)
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
        context.beginClip(x, y, w, h)
    }

    /// 現在のクリップ領域を終了し、前の状態に復元します。
    public func endClip() {
        context.endClip()
    }
}
