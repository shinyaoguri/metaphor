import Metal
import simd

// MARK: - Rect / Ellipse / Image Mode

/// `rect()` 呼び出しにおける座標の解釈方法を定義します。
public enum RectMode: Sendable {
    /// x, y を左上隅、w, h を幅と高さとして解釈（デフォルト）。
    case corner
    /// x, y を左上隅、w, h を右下隅の座標として解釈。
    case corners
    /// x, y を中心、w, h を幅と高さとして解釈。
    case center
    /// x, y を中心、w, h を半幅と半高さとして解釈。
    case radius
}

/// `ellipse()` 呼び出しにおける座標の解釈方法を定義します。
public enum EllipseMode: Sendable {
    /// x, y を中心、w, h を幅と高さとして解釈（デフォルト）。
    case center
    /// x, y を中心、w, h を半径として解釈。
    case radius
    /// x, y を左上隅、w, h を幅と高さとして解釈。
    case corner
    /// x, y を左上隅、w, h を右下隅の座標として解釈。
    case corners
}

/// `image()` 呼び出しにおける座標の解釈方法を定義します。
public enum ImageMode: Sendable {
    /// x, y を左上隅として解釈（デフォルト）。
    case corner
    /// x, y を中心として解釈。
    case center
    /// x, y を左上隅、w, h を右下隅の座標として解釈。
    case corners
}

/// `arc()` 呼び出しの描画モードを指定します。
///
/// Processing 互換の 4 状態。fill と stroke で閉じ方が異なる点に注意
/// （mode 省略時は fill が扇形、stroke は弧のみ、という非対称な組み合わせ）。
public enum ArcMode: Sendable {
    /// mode 省略時のデフォルト。fill は中心を含む扇形、stroke は端点を接続せず弧のみを描画。
    case `default`
    /// fill は弦で閉じた弓形、stroke は端点を接続せず弧のみを描画。
    case open
    /// fill は弦で閉じた弓形、stroke は端点を弦（直線）で接続して閉じる。
    case chord
    /// fill は中心を含む扇形、stroke は端点から中心へ線を引いてパイ形状に閉じる。
    case pie
}

// MARK: - Stroke Cap / Join

/// ストロークの端点に適用されるスタイルを指定します。
public enum StrokeCap: Sendable {
    /// ストロークの端点に丸いキャップを適用（デフォルト）。
    case round
    /// 端点からストローク幅の半分だけ延長する四角いキャップを適用。
    case square
    /// 端点を超えた延長なし。
    case butt
}

/// 接続されたストロークセグメント間の結合スタイルを指定します。
public enum StrokeJoin: Sendable {
    /// 鋭い角でセグメントを結合（デフォルト）。
    case miter
    /// 平らなベベルでセグメントを結合。
    case bevel
    /// 丸い弧でセグメントを結合。
    case round
}

// MARK: - Gradient Axis

/// グラデーション塗りつぶしの方向を指定します。
public enum GradientAxis: Sendable {
    /// 上から下へグラデーションを適用。
    case vertical
    /// 左から右へグラデーションを適用。
    case horizontal
    /// 左上から右下へ斜めにグラデーションを適用。
    case diagonal
}

// MARK: - Shape Mode

/// `beginShape()` で使用されるプリミティブタイプを指定します。
public enum ShapeMode: Sendable {
    /// 任意のポリゴンを描画（デフォルト）。
    case polygon
    /// 個別のポイントの集合を描画。
    case points
    /// 頂点ペアを個別の線分として描画。
    case lines
    /// 3頂点のグループを個別の三角形として描画。
    case triangles
    /// 頂点をトライアングルストリップとして描画。
    case triangleStrip
    /// 頂点をトライアングルファンとして描画。
    case triangleFan
}

/// `endShape()` 呼び出し時にシェイプを閉じるかどうかを指定します。
public enum CloseMode: Sendable {
    /// 最後の頂点と最初の頂点を接続せずシェイプを開いたままにする。
    case open
    /// 最後の頂点と最初の頂点を接続してシェイプを閉じる。
    case close
}
