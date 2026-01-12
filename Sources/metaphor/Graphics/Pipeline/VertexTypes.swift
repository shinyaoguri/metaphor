import simd

/// 2D形状描画用の頂点構造体
/// シェーダーと共有するためメモリレイアウトを明示
public struct ShapeVertex {
    /// 頂点位置（スクリーン座標）
    public var position: SIMD2<Float>

    /// 頂点色（正規化済み0-1）
    public var color: SIMD4<Float>

    /// UV座標（SDF計算用）
    public var uv: SIMD2<Float>

    /// 形状タイプ（0=rect, 1=ellipse, 2=line, 3=point, 4=triangle）
    public var shapeType: UInt32

    /// 追加パラメータ（用途は形状依存）
    public var param1: Float

    public init(
        position: SIMD2<Float>,
        color: SIMD4<Float>,
        uv: SIMD2<Float> = .zero,
        shapeType: UInt32 = 0,
        param1: Float = 0
    ) {
        self.position = position
        self.color = color
        self.uv = uv
        self.shapeType = shapeType
        self.param1 = param1
    }
}

/// 形状タイプの定数
public enum ShapeType: UInt32 {
    case rect = 0
    case ellipse = 1
    case line = 2
    case point = 3
    case triangle = 4
}

/// Uniform構造体（射影行列など）
public struct ShapeUniforms {
    /// 正射影行列（スクリーン座標→NDC）
    public var projection: float4x4

    public init(projection: float4x4) {
        self.projection = projection
    }
}
