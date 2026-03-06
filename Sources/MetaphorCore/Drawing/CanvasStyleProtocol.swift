import simd

/// Protocol for shared style management between Canvas2D and Canvas3D.
///
/// Provides default implementations for fill, stroke, colorMode, and style sync
/// methods, eliminating ~70% of the duplicated code between the two canvas types.
@MainActor
public protocol CanvasStyle: AnyObject {
    var fillColor: SIMD4<Float> { get set }
    var strokeColor: SIMD4<Float> { get set }
    var hasFill: Bool { get set }
    var hasStroke: Bool { get set }
    var colorModeConfig: ColorModeConfig { get set }
}

// MARK: - Default Fill Implementations

extension CanvasStyle {

    public func fill(_ color: Color) {
        fillColor = color.simd
        hasFill = true
    }

    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        fillColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasFill = true
    }

    public func fill(_ gray: Float) {
        fillColor = colorModeConfig.toGray(gray).simd
        hasFill = true
    }

    public func fill(_ gray: Float, _ alpha: Float) {
        fillColor = colorModeConfig.toGray(gray, alpha).simd
        hasFill = true
    }

    public func noFill() {
        hasFill = false
    }
}

// MARK: - Default Stroke Implementations

extension CanvasStyle {

    public func stroke(_ color: Color) {
        strokeColor = color.simd
        hasStroke = true
    }

    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        strokeColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasStroke = true
    }

    public func stroke(_ gray: Float) {
        strokeColor = colorModeConfig.toGray(gray).simd
        hasStroke = true
    }

    public func stroke(_ gray: Float, _ alpha: Float) {
        strokeColor = colorModeConfig.toGray(gray, alpha).simd
        hasStroke = true
    }

    public func noStroke() {
        hasStroke = false
    }
}

// MARK: - Default Color Mode Implementations

extension CanvasStyle {

    public func colorMode(
        _ space: ColorSpace,
        _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxAlpha: Float = 1.0
    ) {
        colorModeConfig = ColorModeConfig(space: space, max1: max1, max2: max2, max3: max3, maxAlpha: maxAlpha)
    }

    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        colorModeConfig = ColorModeConfig(space: space, max1: maxAll, max2: maxAll, max3: maxAll, maxAlpha: maxAll)
    }
}

// MARK: - Default Style Sync

extension CanvasStyle {

    public func syncStyle(_ style: DrawingStyle) {
        fillColor = style.fillColor
        strokeColor = style.strokeColor
        hasFill = style.hasFill
        hasStroke = style.hasStroke
        colorModeConfig = style.colorModeConfig
    }
}
