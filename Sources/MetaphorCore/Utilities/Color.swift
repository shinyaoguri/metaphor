import Metal
import simd

/// An RGBA color with floating-point components.
///
/// Components are expressed on a 0.0 to 1.0 scale, but **they are not forced into that range**.
/// Supports initialization from RGB, HSB, grayscale, and hexadecimal forms.
///
/// ## Out-of-range components
///
/// ``init(r:g:b:alpha:)`` and ``init(gray:alpha:)`` keep their arguments as given instead of clamping them.
/// Out-of-range components also arise on purpose — `Color` conforms to ``Interpolatable`` and extrapolates linearly,
/// so running a `Tween<Color>` with an overshooting easing such as `easeOutBack` or `easeOutElastic` produces
/// components outside 0.0...1.0.
///
/// When such a color is drawn, its components **saturate to 0.0...1.0 at draw time**. This is because the offscreen
/// render target uses a normalized format (`bgra8Unorm`) and the GPU clamps fragment output **before** blending.
/// As a result:
///
/// - `a: 1.5` draws the same as `a: 1.0` (the background is never over-subtracted)
/// - Compositing a negative component with ``BlendMode/additive`` does not darken the background (it is treated as 0)
/// - HDR-style uses that need to retain luminance above 1.0 are not possible
/// - A background color set through ``clearColor`` saturates the same way
///
/// When converting components to another representation (binding them to a shader, converting to `UInt8`,
/// formatting a CSS string, and so on), do not assume 0.0...1.0 as an invariant; clamp on the caller side if needed.
public struct Color: Sendable, Equatable {
    /// The red component, on a 0.0 to 1.0 scale (out-of-range values are preserved).
    public var r: Float
    /// The green component, on a 0.0 to 1.0 scale (out-of-range values are preserved).
    public var g: Float
    /// The blue component, on a 0.0 to 1.0 scale (out-of-range values are preserved).
    public var b: Float
    /// The alpha (opacity) component, on a 0.0 to 1.0 scale (out-of-range values are preserved).
    public var a: Float

    // MARK: - RGB

    /// Creates a color from RGB components on a 0.0 to 1.0 scale.
    ///
    /// The arguments are not clamped. Out-of-range values are preserved as given and
    /// saturate at draw time (see "Out-of-range components" in ``Color``).
    ///
    /// - Parameters:
    ///   - r: The red component.
    ///   - g: The green component.
    ///   - b: The blue component.
    ///   - alpha: The alpha component. The default is 1.0 (fully opaque).
    public init(r: Float, g: Float, b: Float, alpha: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = alpha
    }

    // MARK: - Grayscale

    /// Creates a grayscale color, where 0.0 is black and 1.0 is white.
    ///
    /// As with ``init(r:g:b:alpha:)``, the arguments are not clamped.
    ///
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha component. The default is 1.0 (fully opaque).
    public init(gray: Float, alpha: Float = 1.0) {
        self.r = gray
        self.g = gray
        self.b = gray
        self.a = alpha
    }

    // MARK: - HSB

    /// Creates a color from hue, saturation, and brightness components.
    ///
    /// Unlike the RGB initializers, `saturation` and `brightness` are clamped to 0.0...1.0 here.
    /// This is not a promise about the value range but a guard that preserves the premise of the HSB-to-RGB
    /// conversion — computing with out-of-range values makes the intermediates (`p` / `q` / `t`) meaningless
    /// and produces colors that jump discontinuously from hue to hue.
    /// `hue` wraps with a period of 0.0...1.0, and `alpha` is not clamped.
    ///
    /// - Parameters:
    ///   - hue: The hue value. It completes one turn from 0.0 to 1.0, and out-of-range values wrap around (1.25 is the same as 0.25).
    ///   - saturation: The saturation value. Clamped to the range 0.0 to 1.0.
    ///   - brightness: The brightness value. Clamped to the range 0.0 to 1.0.
    ///   - alpha: The alpha component. The default is 1.0 (fully opaque). Not clamped.
    public init(hue: Float, saturation: Float, brightness: Float, alpha: Float = 1.0) {
        // NaN/∞ の hue は後段の Int(h) 変換でトラップするため 0 にフォールバック
        // （saturation/brightness は下のクランプで防御済み）。
        let safeHue: Float
        if hue.isFinite {
            safeHue = hue
        } else {
            metaphorWarning(
                "Color(hue:saturation:brightness:) received non-finite hue (\(hue)); using 0")
            safeHue = 0
        }
        let h =
            ((safeHue.truncatingRemainder(dividingBy: 1.0)) + 1.0)
            .truncatingRemainder(dividingBy: 1.0) * 6.0
        let s = max(0, min(1, saturation))
        let v = max(0, min(1, brightness))

        if s == 0 {
            self.r = v
            self.g = v
            self.b = v
            self.a = alpha
            return
        }

        let i = Int(h)
        let f = h - Float(i)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))

        switch i % 6 {
        case 0:
            self.r = v
            self.g = t
            self.b = p
        case 1:
            self.r = q
            self.g = v
            self.b = p
        case 2:
            self.r = p
            self.g = v
            self.b = t
        case 3:
            self.r = p
            self.g = q
            self.b = v
        case 4:
            self.r = t
            self.g = p
            self.b = v
        default:
            self.r = v
            self.g = p
            self.b = q
        }
        self.a = alpha
    }

    // MARK: - Hex

    /// Creates a color from an integer hexadecimal value in 0xRRGGBB or 0xAARRGGBB form.
    ///
    /// The number of digits is inferred from **the magnitude of the value**. An integer literal does not keep
    /// its leading `0` in the value, so there is no other clue to tell the two forms apart. As a result
    /// **an alpha of `0x00` cannot be expressed** — `0x00FFFFFF` is the same value as `0xFFFFFF`, so it is read
    /// as RGB and the alpha becomes `1.0`. Build colors that include transparency with
    /// ``init(hex:)-(String)`` (an eight-digit spelling is always read as AARRGGBB) or with ``withAlpha(_:)``.
    ///
    /// - Parameter hex: The hexadecimal color value. Values greater than 0xFFFFFF are interpreted as AARRGGBB.
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

    /// Creates a color from a hexadecimal string in "#RGB", "#RRGGBB", or "#AARRGGBB" form.
    ///
    /// Only **three, six, and eight digits** are accepted; any other digit count, and any string containing
    /// characters other than hexadecimal digits, returns `nil`. Three digits are expanded by doubling each digit,
    /// the same shorthand as CSS ("#FFF" is white).
    ///
    /// **The four-digit shorthand is not accepted.** This library's eight-digit form is AARRGGBB (alpha first),
    /// the reverse of the CSS RRGGBBAA order, so four digits could be read as either ARGB or RGBA. Whichever were
    /// chosen, the other spelling would silently become a different color, so it is returned as `nil`, a misspelling.
    ///
    /// In the eight-digit form an alpha of `00` (fully transparent) is also read exactly as spelled. Because the
    /// digit count is taken from the spelling, the ambiguity that forces ``init(hex:)-(UInt32)`` to infer it from
    /// the magnitude does not arise here.
    ///
    /// - Parameter hex: The hexadecimal color string. The "#" prefix is optional.
    public init?(hex: String) {
        var str = hex
        if str.hasPrefix("#") { str.removeFirst() }
        // 桁数だけでは足りない: `UInt32(_:radix:)` は先頭の符号を受けるので "+FFFFF" が 6 桁として
        // 通ってしまう。全角の "ＦＦＦＦＦＦ" は `isHexDigit` が true になるため `isASCII` も要る。
        guard str.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        // CSS の 3 桁短縮形を展開する（"0AF" → "00AAFF"）。
        if str.count == 3 { str = String(str.flatMap { [$0, $0] }) }
        guard str.count == 6 || str.count == 8, let value = UInt32(str, radix: 16) else {
            return nil
        }
        // `init(hex: UInt32)` へは委譲しない。整数側は値の大小で桁数を判別するため
        // `0x00FFFFFF == 0xFFFFFF` が RGB として読まれ、アルファ 00 だけが 1.0 に化ける。
        // ここは綴りの長さで桁数が分かるので、8 桁は無条件に AARRGGBB として分解する。
        self.a = str.count == 8 ? Float((value >> 24) & 0xFF) / 255.0 : 1.0
        self.r = Float((value >> 16) & 0xFF) / 255.0
        self.g = Float((value >> 8) & 0xFF) / 255.0
        self.b = Float(value & 0xFF) / 255.0
    }

    // MARK: - SIMD Conversion

    /// The color as a `SIMD4<Float>` in (r, g, b, a) order.
    public var simd: SIMD4<Float> {
        SIMD4<Float>(r, g, b, a)
    }

    /// Creates a color from a `SIMD4<Float>` vector interpreted as (r, g, b, a).
    ///
    /// - Parameter simd: The SIMD vector holding the color components.
    public init(_ simd: SIMD4<Float>) {
        self.r = simd.x
        self.g = simd.y
        self.b = simd.z
        self.a = simd.w
    }

    // MARK: - Metal Conversion

    /// The color as an `MTLClearColor` for use in a Metal render pass.
    ///
    /// The components are passed through without clamping. Out-of-range values saturate to 0.0...1.0 on clear.
    public var clearColor: MTLClearColor {
        MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    // MARK: - Color Manipulation

    /// Returns a new color with the given alpha value.
    ///
    /// - Parameter alpha: The new alpha value.
    /// - Returns: A copy of this color with the given alpha.
    public func withAlpha(_ alpha: Float) -> Color {
        Color(r: r, g: g, b: b, alpha: alpha)
    }

    /// Linearly interpolates between this color and another color.
    ///
    /// - Parameters:
    ///   - other: The target color.
    ///   - t: The interpolation factor. Clamped to the range 0...1.
    /// - Returns: The interpolated color.
    public func lerp(to other: Color, t: Float) -> Color {
        let t = max(0, min(1, t))
        return Color(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t,
            alpha: a + (other.a - a) * t
        )
    }

    // MARK: - HSB Components

    /// The hue of this color, on a 0.0 to 1.0 scale.
    ///
    /// This is the inverse of ``init(hue:saturation:brightness:alpha:)``: feeding ``hue``,
    /// ``saturation``, ``brightness`` and ``a`` back into that initializer reproduces the color.
    ///
    /// - Important: The value is **on a 0.0 to 1.0 scale and ignores `colorMode()`**, exactly like
    ///   ``r``, ``g``, ``b`` and ``a``. Under `colorMode(.hsb, 360, 100, 100)` a Processing sketch
    ///   expects `hue(c)` to be 0 to 360, so scale it yourself: `hue(c) * 360`.
    ///
    /// - Note: One full turn is 0.0 to 1.0 and the value never reaches 1.0 — pure red is 0.0, not
    ///   1.0. For a gray color (``saturation`` of 0) the hue is undefined and 0.0 is returned,
    ///   as in Processing.
    public var hue: Float { hsbComponents.hue }

    /// The saturation of this color, on a 0.0 to 1.0 scale.
    ///
    /// - Important: The value is **on a 0.0 to 1.0 scale and ignores `colorMode()`**, exactly like
    ///   ``r``, ``g``, ``b`` and ``a``. Under `colorMode(.hsb, 360, 100, 100)` a Processing sketch
    ///   expects `saturation(c)` to be 0 to 100, so scale it yourself: `saturation(c) * 100`.
    ///
    /// - Note: Black has a saturation of 0.0.
    public var saturation: Float { hsbComponents.saturation }

    /// The brightness of this color, on a 0.0 to 1.0 scale.
    ///
    /// - Important: The value is **on a 0.0 to 1.0 scale and ignores `colorMode()`**, exactly like
    ///   ``r``, ``g``, ``b`` and ``a``. Under `colorMode(.hsb, 360, 100, 100)` a Processing sketch
    ///   expects `brightness(c)` to be 0 to 100, so scale it yourself: `brightness(c) * 100`.
    ///
    /// - Note: This is the largest of the three RGB components (the HSB "value"), not a perceptual
    ///   luminance — pure blue and pure white both report 1.0.
    public var brightness: Float { hsbComponents.brightness }

    /// Converts the RGB components into hue, saturation and brightness.
    ///
    /// The RGB components are clamped into 0.0...1.0 first, and non-finite components are read as
    /// 0.0. This mirrors ``init(hue:saturation:brightness:alpha:)``, which clamps `saturation` and
    /// `brightness` for the same reason: the conversion is only meaningful on a bounded cube, and
    /// out-of-range components saturate at draw time anyway (see "Out-of-range components" in
    /// ``Color``). Reading a color back therefore reports it **as it is drawn**.
    private var hsbComponents: (hue: Float, saturation: Float, brightness: Float) {
        // 読み出しアクセサは決して落ちない（ADR-0005 / #356）。NaN/∞ は 0 として読む。
        func normalized(_ value: Float) -> Float {
            value.isFinite ? max(0, min(1, value)) : 0
        }
        let r = normalized(self.r)
        let g = normalized(self.g)
        let b = normalized(self.b)

        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC

        let brightness = maxC
        let saturation = maxC == 0 ? 0 : delta / maxC

        guard delta > 0 else {
            // 無彩色。色相は数学的に未定義なので Processing と同じく 0 を返す。
            return (0, saturation, brightness)
        }

        let sector: Float
        if maxC == r {
            sector = (g - b) / delta
        } else if maxC == g {
            sector = 2 + (b - r) / delta
        } else {
            sector = 4 + (r - g) / delta
        }
        // 6 セクタを 0.0..<1.0 へ畳む。赤より下側（負）は 1 周ぶん足して巻き戻す。
        let hue = sector < 0 ? sector / 6 + 1 : sector / 6

        return (hue, saturation, brightness)
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
    public static let clear = Color(r: 0, g: 0, b: 0, alpha: 0)
}

// MARK: - Global Color Functions

/// Linearly interpolates between two colors.
///
/// - Parameters:
///   - c1: The starting color.
///   - c2: The ending color.
///   - t: The interpolation factor.
/// - Returns: The interpolated color.
public func lerpColor(_ c1: Color, _ c2: Color, _ t: Float) -> Color {
    c1.lerp(to: c2, t: t)
}

// MARK: - Component Extraction

/// Extracts the hue of a color (compatible with Processing's `hue()`).
///
/// ```swift
/// let c = Color(hue: 0.55, saturation: 0.8, brightness: 1.0)
/// let shifted = Color(hue: hue(c) + 0.1, saturation: saturation(c), brightness: brightness(c))
/// ```
///
/// - Important: The result is **on a 0.0 to 1.0 scale and ignores `colorMode()`**, unlike
///   Processing, where `hue()` follows the current color mode. metaphor draws the line between the
///   two scales at the type: the numeric `fill` / `stroke` / `background` / `tint` overloads follow
///   `colorMode()`, while ``Color`` values are always normalized. These extractors take a ``Color``
///   and are the exact inverse of ``Color/init(hue:saturation:brightness:alpha:)``, so they stay on
///   the normalized side. Porting `colorMode(HSB, 360, 100, 100)` code means scaling by hand:
///   `hue(c) * 360`.
///
/// - Note: One full turn is 0.0 to 1.0 and the value never reaches 1.0 — pure red is 0.0. A gray
///   color returns 0.0, as in Processing.
///
/// - Note: Swift does not keep functions and variables in separate namespaces, so a local named
///   `hue` shadows this function inside its scope. Use the ``Color/hue`` property instead there.
///
/// - Parameter c: The color to read.
/// - Returns: The hue, from 0.0 up to (but not including) 1.0.
public func hue(_ c: Color) -> Float {
    c.hue
}

/// Extracts the saturation of a color (compatible with Processing's `saturation()`).
///
/// - Important: The result is **on a 0.0 to 1.0 scale and ignores `colorMode()`**, unlike
///   Processing. See ``hue(_:)`` for why, and scale by hand when porting:
///   `saturation(c) * 100` under `colorMode(HSB, 360, 100, 100)`.
///
/// - Note: A local named `saturation` shadows this function inside its scope; use the
///   ``Color/saturation`` property there.
///
/// - Parameter c: The color to read.
/// - Returns: The saturation, from 0.0 to 1.0.
public func saturation(_ c: Color) -> Float {
    c.saturation
}

/// Extracts the brightness of a color (compatible with Processing's `brightness()`).
///
/// - Important: The result is **on a 0.0 to 1.0 scale and ignores `colorMode()`**, unlike
///   Processing. See ``hue(_:)`` for why, and scale by hand when porting:
///   `brightness(c) * 100` under `colorMode(HSB, 360, 100, 100)`.
///
/// - Note: This is the largest of the three RGB components (the HSB "value"), not a perceptual
///   luminance. A local named `brightness` shadows this function inside its scope; use the
///   ``Color/brightness`` property there.
///
/// - Parameter c: The color to read.
/// - Returns: The brightness, from 0.0 to 1.0.
public func brightness(_ c: Color) -> Float {
    c.brightness
}

/// Extracts the red component of a color (compatible with Processing's `red()`).
///
/// - Important: The result is **on a 0.0 to 1.0 scale and ignores `colorMode()`**, unlike
///   Processing. Ported code such as `fill(red(c), green(c), blue(c))` therefore compiles but draws
///   almost black under the default `colorMode(.rgb, 255)` — pass the ``Color`` straight to
///   `fill(_:)` instead, or scale by hand with `red(c) * 255`. See ``hue(_:)`` for the reasoning.
///
/// - Note: This returns ``Color/r`` unchanged, including components outside 0.0...1.0 (see
///   "Out-of-range components" in ``Color``). A local named `red` shadows this function inside its
///   scope; use the ``Color/r`` property there.
///
/// - Parameter c: The color to read.
/// - Returns: The red component.
public func red(_ c: Color) -> Float {
    c.r
}

/// Extracts the green component of a color (compatible with Processing's `green()`).
///
/// - Important: The result is **on a 0.0 to 1.0 scale and ignores `colorMode()`**, unlike
///   Processing. See ``red(_:)`` for the porting trap and ``hue(_:)`` for the reasoning.
///
/// - Note: This returns ``Color/g`` unchanged, including out-of-range components. A local named
///   `green` shadows this function inside its scope; use the ``Color/g`` property there.
///
/// - Parameter c: The color to read.
/// - Returns: The green component.
public func green(_ c: Color) -> Float {
    c.g
}

/// Extracts the blue component of a color (compatible with Processing's `blue()`).
///
/// - Important: The result is **on a 0.0 to 1.0 scale and ignores `colorMode()`**, unlike
///   Processing. See ``red(_:)`` for the porting trap and ``hue(_:)`` for the reasoning.
///
/// - Note: This returns ``Color/b`` unchanged, including out-of-range components. A local named
///   `blue` shadows this function inside its scope; use the ``Color/b`` property there.
///
/// - Parameter c: The color to read.
/// - Returns: The blue component.
public func blue(_ c: Color) -> Float {
    c.b
}

/// Extracts the alpha component of a color (compatible with Processing's `alpha()`).
///
/// - Important: The result is **on a 0.0 to 1.0 scale and ignores `colorMode()`**, unlike
///   Processing, where `alpha()` follows `maxAlpha`. It is straight (non-premultiplied) alpha,
///   as everywhere in the public API (ADR-0012). See ``hue(_:)`` for the reasoning.
///
/// - Note: This returns ``Color/a`` unchanged, including out-of-range components. A local named
///   `alpha` shadows this function inside its scope; use the ``Color/a`` property there.
///
/// - Parameter c: The color to read.
/// - Returns: The alpha component, where 0.0 is fully transparent and 1.0 fully opaque.
public func alpha(_ c: Color) -> Float {
    c.a
}

// MARK: - Color Space

/// Defines the color space used to interpret colors.
public enum ColorSpace: Sendable {
    /// The red, green, and blue color space.
    case rgb
    /// The hue, saturation, and brightness color space.
    case hsb
}

// MARK: - Color Mode Config

/// Holds the configuration of the `colorMode()` function.
///
/// Normalizes the values the user supplies and converts them into ``Color`` instances.
public struct ColorModeConfig: Sendable, Equatable {
    /// The active color space.
    public var space: ColorSpace = .rgb
    /// The maximum value of the first component (red or hue).
    public var max1: Float = 255.0
    /// The maximum value of the second component (green or saturation).
    public var max2: Float = 255.0
    /// The maximum value of the third component (blue or brightness).
    public var max3: Float = 255.0
    /// The maximum value of the alpha component.
    public var maxAlpha: Float = 255.0

    /// Converts three component values and an optional alpha into a color.
    ///
    /// Each component is only normalized by dividing it by the corresponding maximum; the upper bound is not enforced.
    /// Passing input above the maximum, such as `fill(300)` against the default `max1 = 255`, yields a ``Color``
    /// whose components fall outside 0.0...1.0 in ``ColorSpace/rgb`` (they saturate at draw time).
    /// In ``ColorSpace/hsb``, ``Color/init(hue:saturation:brightness:alpha:)`` clamps saturation and brightness,
    /// and the hue wraps around.
    ///
    /// - Parameters:
    ///   - v1: The first component value (red or hue).
    ///   - v2: The second component value (green or saturation).
    ///   - v3: The third component value (blue or brightness).
    ///   - alpha: The alpha value. When `nil`, `maxAlpha` is used as the default.
    /// - Returns: A color with normalized components.
    public func toColor(_ v1: Float, _ v2: Float, _ v3: Float, _ alpha: Float? = nil) -> Color {
        let nA = (alpha ?? maxAlpha) / maxAlpha
        switch space {
        case .rgb:
            return Color(r: v1 / max1, g: v2 / max2, b: v3 / max3, alpha: nA)
        case .hsb:
            return Color(hue: v1 / max1, saturation: v2 / max2, brightness: v3 / max3, alpha: nA)
        }
    }

    /// Converts a grayscale value and an optional alpha into a color.
    ///
    /// As with ``toColor(_:_:_:_:)``, it only divides by `max1`; the upper bound is not enforced.
    ///
    /// - Parameters:
    ///   - gray: The grayscale value.
    ///   - alpha: The alpha value. When `nil`, `maxAlpha` is used as the default.
    /// - Returns: A grayscale color with normalized components.
    public func toGray(_ gray: Float, _ alpha: Float? = nil) -> Color {
        let nA = (alpha ?? maxAlpha) / maxAlpha
        return Color(gray: gray / max1, alpha: nA)
    }
}
