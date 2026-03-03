import simd

/// Hold drawing style properties shared between Canvas2D and Canvas3D.
///
/// SketchContext's fill/stroke/colorMode methods serve as the source of truth,
/// updating this struct and synchronizing it to both canvases.
public struct DrawingStyle: Sendable {
    /// Fill color (RGBA).
    public var fillColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    /// Stroke color (RGBA).
    public var strokeColor: SIMD4<Float> = SIMD4(0, 0, 0, 1)

    /// Whether fill is enabled.
    public var hasFill: Bool = true

    /// Whether stroke is enabled.
    public var hasStroke: Bool = true

    /// Color mode configuration.
    public var colorModeConfig: ColorModeConfig = ColorModeConfig()
}
