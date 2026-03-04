import Metal
import simd

/// Represents an RGBA color with floating-point components.
///
/// All component values are in the range 0.0 to 1.0.
/// Supports initialization from RGB, HSB, grayscale, and hex formats.
public struct Color: Sendable, Equatable {
    /// The red component, in the range 0.0 to 1.0.
    public var r: Float
    /// The green component, in the range 0.0 to 1.0.
    public var g: Float
    /// The blue component, in the range 0.0 to 1.0.
    public var b: Float
    /// The alpha (opacity) component, in the range 0.0 to 1.0.
    public var a: Float

    // MARK: - RGB

    /// Creates a color from RGB components in the range 0.0 to 1.0.
    ///
    /// - Parameters:
    ///   - r: The red component.
    ///   - g: The green component.
    ///   - b: The blue component.
    ///   - a: The alpha component. Defaults to 1.0 (fully opaque).
    public init(r: Float, g: Float, b: Float, a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    // MARK: - Grayscale

    /// Creates a grayscale color where 0.0 is black and 1.0 is white.
    ///
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha component. Defaults to 1.0 (fully opaque).
    public init(gray: Float, alpha: Float = 1.0) {
        self.r = gray
        self.g = gray
        self.b = gray
        self.a = alpha
    }

    // MARK: - HSB

    /// Creates a color from hue, saturation, and brightness components.
    ///
    /// - Parameters:
    ///   - hue: The hue value in the range 0.0 to 1.0.
    ///   - saturation: The saturation value in the range 0.0 to 1.0.
    ///   - brightness: The brightness value in the range 0.0 to 1.0.
    ///   - alpha: The alpha component. Defaults to 1.0 (fully opaque).
    public init(hue: Float, saturation: Float, brightness: Float, alpha: Float = 1.0) {
        let h = ((hue.truncatingRemainder(dividingBy: 1.0)) + 1.0)
            .truncatingRemainder(dividingBy: 1.0) * 6.0
        let s = max(0, min(1, saturation))
        let v = max(0, min(1, brightness))

        if s == 0 {
            self.r = v; self.g = v; self.b = v; self.a = alpha
            return
        }

        let i = Int(h)
        let f = h - Float(i)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))

        switch i % 6 {
        case 0: self.r = v; self.g = t; self.b = p
        case 1: self.r = q; self.g = v; self.b = p
        case 2: self.r = p; self.g = v; self.b = t
        case 3: self.r = p; self.g = q; self.b = v
        case 4: self.r = t; self.g = p; self.b = v
        default: self.r = v; self.g = p; self.b = q
        }
        self.a = alpha
    }

    // MARK: - Hex

    /// Creates a color from an integer hex value in the format 0xRRGGBB or 0xAARRGGBB.
    ///
    /// - Parameter hex: The hex color value. Values greater than 0xFFFFFF are treated as AARRGGBB.
    public init(hex: UInt32) {
        if hex > 0xFFFFFF {
            self.a = Float((hex >> 24) & 0xFF) / 255.0
            self.r = Float((hex >> 16) & 0xFF) / 255.0
            self.g = Float((hex >> 8) & 0xFF) / 255.0
            self.b = Float(hex & 0xFF) / 255.0
        } else {
            self.r = Float((hex >> 16) & 0xFF) / 255.0
            self.g = Float((hex >> 8) & 0xFF) / 255.0
            self.b = Float(hex & 0xFF) / 255.0
            self.a = 1.0
        }
    }

    /// Creates a color from a hex string in the format "#RRGGBB" or "#AARRGGBB".
    ///
    /// - Parameter hex: The hex color string, optionally prefixed with "#".
    public init?(hex: String) {
        var str = hex
        if str.hasPrefix("#") { str.removeFirst() }
        guard let value = UInt32(str, radix: 16) else { return nil }
        self.init(hex: value)
    }

    // MARK: - SIMD Conversion

    /// Returns the color as a `SIMD4<Float>` in (r, g, b, a) order.
    public var simd: SIMD4<Float> {
        SIMD4<Float>(r, g, b, a)
    }

    /// Creates a color from a `SIMD4<Float>` vector interpreted as (r, g, b, a).
    ///
    /// - Parameter simd: The SIMD vector containing color components.
    public init(_ simd: SIMD4<Float>) {
        self.r = simd.x
        self.g = simd.y
        self.b = simd.z
        self.a = simd.w
    }

    // MARK: - Metal Conversion

    /// Returns the color as an `MTLClearColor` for use with Metal render passes.
    public var clearColor: MTLClearColor {
        MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    // MARK: - Color Manipulation

    /// Returns a new color with the specified alpha value.
    ///
    /// - Parameter alpha: The new alpha value.
    /// - Returns: A copy of this color with the given alpha.
    public func withAlpha(_ alpha: Float) -> Color {
        Color(r: r, g: g, b: b, a: alpha)
    }

    /// Performs linear interpolation between this color and another.
    ///
    /// - Parameters:
    ///   - other: The target color.
    ///   - t: The interpolation factor, clamped to the range 0...1.
    /// - Returns: The interpolated color.
    public func lerp(to other: Color, t: Float) -> Color {
        let t = max(0, min(1, t))
        return Color(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t,
            a: a + (other.a - a) * t
        )
    }

    // MARK: - Named Colors

    /// Pure black.
    public static let black = Color(gray: 0)
    /// Pure white.
    public static let white = Color(gray: 1)
    /// Pure red.
    public static let red = Color(r: 1, g: 0, b: 0)
    /// Pure green.
    public static let green = Color(r: 0, g: 1, b: 0)
    /// Pure blue.
    public static let blue = Color(r: 0, g: 0, b: 1)
    /// Pure yellow.
    public static let yellow = Color(r: 1, g: 1, b: 0)
    /// Pure cyan.
    public static let cyan = Color(r: 0, g: 1, b: 1)
    /// Pure magenta.
    public static let magenta = Color(r: 1, g: 0, b: 1)
    /// Orange.
    public static let orange = Color(r: 1, g: 0.6, b: 0)
    /// Fully transparent black.
    public static let clear = Color(r: 0, g: 0, b: 0, a: 0)
}

// MARK: - Global Color Functions

/// Performs linear interpolation between two colors.
///
/// - Parameters:
///   - c1: The starting color.
///   - c2: The ending color.
///   - t: The interpolation factor.
/// - Returns: The interpolated color.
public func lerpColor(_ c1: Color, _ c2: Color, _ t: Float) -> Color {
    c1.lerp(to: c2, t: t)
}

// MARK: - Color Space

/// Defines the color space used for color interpretation.
public enum ColorSpace: Sendable {
    /// Red, green, blue color space.
    case rgb
    /// Hue, saturation, brightness color space.
    case hsb
}

// MARK: - Color Mode Config

/// Holds the configuration for the `colorMode()` function.
///
/// Normalizes user-specified values and converts them into a ``Color`` instance.
public struct ColorModeConfig: Sendable, Equatable {
    /// The active color space.
    public var space: ColorSpace = .rgb
    /// The maximum value for the first component (red or hue).
    public var max1: Float = 255.0
    /// The maximum value for the second component (green or saturation).
    public var max2: Float = 255.0
    /// The maximum value for the third component (blue or brightness).
    public var max3: Float = 255.0
    /// The maximum value for the alpha component.
    public var maxAlpha: Float = 255.0

    /// Converts three component values and an optional alpha into a color.
    ///
    /// - Parameters:
    ///   - v1: The first component value (red or hue).
    ///   - v2: The second component value (green or saturation).
    ///   - v3: The third component value (blue or brightness).
    ///   - alpha: The alpha value. Defaults to `maxAlpha` when `nil`.
    /// - Returns: The resulting color with normalized components.
    public func toColor(_ v1: Float, _ v2: Float, _ v3: Float, _ alpha: Float? = nil) -> Color {
        let nA = (alpha ?? maxAlpha) / maxAlpha
        switch space {
        case .rgb:
            return Color(r: v1 / max1, g: v2 / max2, b: v3 / max3, a: nA)
        case .hsb:
            return Color(hue: v1 / max1, saturation: v2 / max2, brightness: v3 / max3, alpha: nA)
        }
    }

    /// Converts a grayscale value and an optional alpha into a color.
    ///
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha value. Defaults to `maxAlpha` when `nil`.
    /// - Returns: The resulting grayscale color with normalized components.
    public func toGray(_ gray: Float, _ alpha: Float? = nil) -> Color {
        let nA = (alpha ?? maxAlpha) / maxAlpha
        return Color(gray: gray / max1, alpha: nA)
    }
}
