import Metal
import simd

// MARK: - Rect / Ellipse / Image Mode

/// rect()の座標解釈モード
public enum RectMode: Sendable {
    /// x,y = 左上角、w,h = 幅と高さ（デフォルト）
    case corner
    /// x,y = 左上角、w,h = 右下角の座標
    case corners
    /// x,y = 中心、w,h = 幅と高さ
    case center
    /// x,y = 中心、w,h = 半幅と半高
    case radius
}

/// ellipse()の座標解釈モード
public enum EllipseMode: Sendable {
    /// x,y = 中心、w,h = 幅と高さ（デフォルト）
    case center
    /// x,y = 中心、w,h = 半径
    case radius
    /// x,y = 左上角、w,h = 幅と高さ
    case corner
    /// x,y = 左上角、w,h = 右下角の座標
    case corners
}

/// image()の座標解釈モード
public enum ImageMode: Sendable {
    /// x,y = 左上角（デフォルト）
    case corner
    /// x,y = 中心
    case center
    /// x,y = 左上角、w,h = 右下角の座標
    case corners
}

/// arc()の描画モード
public enum ArcMode: Sendable {
    /// 弧のみ（端点を接続しない）
    case open
    /// 端点間を直線で接続
    case chord
    /// 端点から中心への線（パイ型）
    case pie
}

// MARK: - Stroke Cap / Join

/// ストロークの端点スタイル
public enum StrokeCap: Sendable {
    /// 丸型（Processing デフォルト）
    case round
    /// 正方形（半strokeWeight分延長）
    case square
    /// 延長なし
    case butt
}

/// ストロークの接合スタイル
public enum StrokeJoin: Sendable {
    /// 鋭角接合（デフォルト）
    case miter
    /// 平面接合
    case bevel
    /// 円弧接合
    case round
}

// MARK: - Gradient Axis

/// グラデーションの方向
public enum GradientAxis: Sendable {
    /// 上から下
    case vertical
    /// 左から右
    case horizontal
    /// 左上から右下
    case diagonal
}

// MARK: - Shape Mode

/// beginShape()で使用する形状モード
public enum ShapeMode: Sendable {
    /// 任意の多角形（デフォルト）
    case polygon
    /// 点の集合
    case points
    /// 線分のペア
    case lines
    /// 三角形の列（3頂点ずつ）
    case triangles
    /// トライアングルストリップ
    case triangleStrip
    /// トライアングルファン
    case triangleFan
}

/// endShape()で使用する閉じモード
public enum CloseMode: Sendable {
    /// 形状を閉じない
    case open
    /// 最後の頂点と最初の頂点を接続して閉じる
    case close
}

// MARK: - Errors

public enum Canvas2DError: Error {
    case bufferCreationFailed
}
