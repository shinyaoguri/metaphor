import simd

/// Canvas2D と Canvas3D に共通する描画スタイル
///
/// SketchContext の fill/stroke/colorMode が source of truth として
/// この構造体を更新し、両 Canvas に同期する。
public struct DrawingStyle: Sendable {
    /// フィルカラー (RGBA)
    public var fillColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    /// ストロークカラー (RGBA)
    public var strokeColor: SIMD4<Float> = SIMD4(0, 0, 0, 1)

    /// フィルの有効フラグ
    public var hasFill: Bool = true

    /// ストロークの有効フラグ
    public var hasStroke: Bool = true

    /// カラーモード設定
    public var colorModeConfig: ColorModeConfig = ColorModeConfig()
}
