import simd

/// Canvas2D と Canvas3D で共有される描画スタイルプロパティを保持します。
///
/// SketchContext の fill/stroke/colorMode メソッドが信頼できるソースとして機能し、
/// この構造体を更新して両方のキャンバスに同期します。
public struct DrawingStyle: Sendable {
    /// 塗りつぶし色（RGBA）。
    public var fillColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    /// ストローク色（RGBA）。
    public var strokeColor: SIMD4<Float> = SIMD4(0, 0, 0, 1)

    /// 塗りつぶしが有効かどうか。
    public var hasFill: Bool = true

    /// ストロークが有効かどうか。
    public var hasStroke: Bool = true

    /// カラーモード設定。
    public var colorModeConfig: ColorModeConfig = ColorModeConfig()
}
