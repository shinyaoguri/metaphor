import simd

/// Canvas2D と Canvas3D の間で共有されるスタイル管理プロトコル。
///
/// fill、stroke、colorMode、スタイル同期メソッドのデフォルト実装を提供し、
/// 2つのキャンバスタイプ間の重複コードを約70%削減します。
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

    /// 最大値を検証します。0 以下・非有限は toColor/toGray のゼロ除算で以降の
    /// 全色が NaN になり描画が黙って消えるため、warning を出して現在値を維持する。
    private func validatedMax(_ value: Float?, current: Float, label: String) -> Float {
        guard let value else { return current }
        guard value.isFinite, value > 0 else {
            metaphorWarning("colorMode: \(label) must be a positive finite value (got \(value)); keeping \(current)")
            return current
        }
        return value
    }

    public func colorMode(
        _ space: ColorSpace,
        _ max1: Float? = nil, _ max2: Float? = nil, _ max3: Float? = nil, _ maxAlpha: Float? = nil
    ) {
        // Processing 互換: 未指定のチャンネルは現在の最大値を維持する。
        // （以前は未指定チャンネルが 1.0 に黙ってリセットされ、colorMode(.hsb)
        // のような呼び出しが全チャンネルのレンジを変えてしまっていた。）
        let current = colorModeConfig
        colorModeConfig = ColorModeConfig(
            space: space,
            max1: validatedMax(max1, current: current.max1, label: "max1"),
            max2: validatedMax(max2, current: current.max2, label: "max2"),
            max3: validatedMax(max3, current: current.max3, label: "max3"),
            maxAlpha: validatedMax(maxAlpha, current: current.maxAlpha, label: "maxAlpha"))
    }

    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        let current = colorModeConfig
        let safe = validatedMax(maxAll, current: current.max1, label: "max")
        colorModeConfig = ColorModeConfig(space: space, max1: safe, max2: safe, max3: safe, maxAlpha: safe)
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
