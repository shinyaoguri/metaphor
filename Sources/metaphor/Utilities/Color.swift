import Metal
import simd

/// RGBA色表現
///
/// 全ての値は0.0〜1.0の範囲。
/// RGB、HSB、グレースケール、hex形式の初期化に対応。
public struct Color: Sendable, Equatable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    // MARK: - RGB

    /// RGBコンポーネントから生成（0.0〜1.0）
    public init(r: Float, g: Float, b: Float, a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    // MARK: - Grayscale

    /// グレースケールから生成（0.0 = 黒、1.0 = 白）
    public init(gray: Float, alpha: Float = 1.0) {
        self.r = gray
        self.g = gray
        self.b = gray
        self.a = alpha
    }

    // MARK: - HSB

    /// HSB（色相・彩度・明度）から生成
    /// - Parameters:
    ///   - hue: 色相 0.0〜1.0
    ///   - saturation: 彩度 0.0〜1.0
    ///   - brightness: 明度 0.0〜1.0
    ///   - alpha: 不透明度 0.0〜1.0
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

    /// hex値から生成（0xRRGGBB または 0xAARRGGBB）
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

    /// hex文字列から生成（"#RRGGBB" または "#AARRGGBB"）
    public init?(hex: String) {
        var str = hex
        if str.hasPrefix("#") { str.removeFirst() }
        guard let value = UInt32(str, radix: 16) else { return nil }
        self.init(hex: value)
    }

    // MARK: - SIMD Conversion

    /// SIMD4<Float>表現 (r, g, b, a)
    public var simd: SIMD4<Float> {
        SIMD4<Float>(r, g, b, a)
    }

    /// SIMD4<Float>から生成
    public init(_ simd: SIMD4<Float>) {
        self.r = simd.x
        self.g = simd.y
        self.b = simd.z
        self.a = simd.w
    }

    // MARK: - Metal Conversion

    /// MTLClearColor表現
    public var clearColor: MTLClearColor {
        MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    // MARK: - Color Manipulation

    /// アルファ値を変更した新しい色を返す
    public func withAlpha(_ alpha: Float) -> Color {
        Color(r: r, g: g, b: b, a: alpha)
    }

    /// 2つの色の線形補間
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

    public static let black = Color(gray: 0)
    public static let white = Color(gray: 1)
    public static let red = Color(r: 1, g: 0, b: 0)
    public static let green = Color(r: 0, g: 1, b: 0)
    public static let blue = Color(r: 0, g: 0, b: 1)
    public static let yellow = Color(r: 1, g: 1, b: 0)
    public static let cyan = Color(r: 0, g: 1, b: 1)
    public static let magenta = Color(r: 1, g: 0, b: 1)
    public static let orange = Color(r: 1, g: 0.6, b: 0)
    public static let clear = Color(r: 0, g: 0, b: 0, a: 0)
}

// MARK: - Color Space

/// 色空間
public enum ColorSpace: Sendable {
    case rgb
    case hsb
}

// MARK: - Color Mode Config

/// colorMode()の設定を保持する構造体
///
/// ユーザーが指定した値を正規化してColorに変換する。
public struct ColorModeConfig: Sendable, Equatable {
    public var space: ColorSpace = .rgb
    public var max1: Float = 1.0   // R or H の最大値
    public var max2: Float = 1.0   // G or S の最大値
    public var max3: Float = 1.0   // B or B の最大値
    public var maxAlpha: Float = 1.0

    /// 3値+αからColorに変換
    public func toColor(_ v1: Float, _ v2: Float, _ v3: Float, _ alpha: Float? = nil) -> Color {
        let nA = (alpha ?? maxAlpha) / maxAlpha
        switch space {
        case .rgb:
            return Color(r: v1 / max1, g: v2 / max2, b: v3 / max3, a: nA)
        case .hsb:
            return Color(hue: v1 / max1, saturation: v2 / max2, brightness: v3 / max3, alpha: nA)
        }
    }

    /// グレースケール+αからColorに変換
    public func toGray(_ gray: Float, _ alpha: Float? = nil) -> Color {
        let nA = (alpha ?? maxAlpha) / maxAlpha
        return Color(gray: gray / max1, alpha: nA)
    }
}
