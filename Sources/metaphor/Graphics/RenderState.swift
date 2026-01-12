import simd

/// 描画モード: 四角形の座標解釈方法
public enum RectMode: Sendable {
    /// (x, y)が左上角、(w, h)がサイズ（デフォルト）
    case corner
    /// (x, y)が左上角、(w, h)が右下角の座標
    case corners
    /// (x, y)が中心、(w, h)がサイズ
    case center
    /// (x, y)が中心、(w, h)が半径
    case radius
}

/// 描画モード: 楕円の座標解釈方法
public enum EllipseMode: Sendable {
    /// (x, y)が中心、(w, h)が直径（デフォルト）
    case center
    /// (x, y)が中心、(w, h)が半径
    case radius
    /// (x, y)が左上角、(w, h)がサイズ
    case corner
    /// (x, y)が左上角、(w, h)が右下角の座標
    case corners
}

/// 頂点形状の種類
public enum ShapeKind: Sendable {
    case points
    case lines
    case triangles
    case triangleStrip
    case triangleFan
    case quads
    case quadStrip
    case polygon
}

/// 形状を閉じるかどうか
public enum CloseMode: Sendable {
    case open
    case close
}

/// 描画状態を保持する構造体
/// pushMatrix/popMatrixで保存・復元される
public struct RenderState: Sendable {
    /// 塗りつぶし色（nilの場合は塗りつぶしなし）
    public var fillColor: Color?

    /// 線の色（nilの場合は線なし）
    public var strokeColor: Color?

    /// 線の太さ
    public var strokeWeight: Float

    /// 変換行列
    public var transform: float4x4

    /// 四角形の描画モード
    public var rectMode: RectMode

    /// 楕円の描画モード
    public var ellipseMode: EllipseMode

    /// デフォルトの描画状態
    public static let `default` = RenderState(
        fillColor: Color(255),
        strokeColor: Color(0),
        strokeWeight: 1.0,
        transform: .identity,
        rectMode: .corner,
        ellipseMode: .center
    )

    public init(
        fillColor: Color? = Color(255),
        strokeColor: Color? = Color(0),
        strokeWeight: Float = 1.0,
        transform: float4x4 = .identity,
        rectMode: RectMode = .corner,
        ellipseMode: EllipseMode = .center
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWeight = strokeWeight
        self.transform = transform
        self.rectMode = rectMode
        self.ellipseMode = ellipseMode
    }
}
