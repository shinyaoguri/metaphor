import simd

/// Processing互換の色表現
/// デフォルトは0-255のRGBモード
public struct Color: Sendable, Equatable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    // MARK: - Initializers (Processing風)

    /// グレースケール（0-255）
    public init(_ gray: Float, _ alpha: Float = 255) {
        self.r = gray
        self.g = gray
        self.b = gray
        self.a = alpha
    }

    /// RGB（0-255）
    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// 正規化されたRGBA（0-1）から生成
    public init(normalized: SIMD4<Float>) {
        self.r = normalized.x * 255
        self.g = normalized.y * 255
        self.b = normalized.z * 255
        self.a = normalized.w * 255
    }

    // MARK: - Computed Properties

    /// 0-1に正規化されたSIMD4を取得
    public var normalized: SIMD4<Float> {
        SIMD4<Float>(r / 255, g / 255, b / 255, a / 255)
    }

    /// MTLClearColorとして取得
    public var clearColor: MTLClearColor {
        MTLClearColor(
            red: Double(r / 255),
            green: Double(g / 255),
            blue: Double(b / 255),
            alpha: Double(a / 255)
        )
    }

    // MARK: - Presets

    public static let white = Color(255)
    public static let black = Color(0)
    public static let red = Color(255, 0, 0)
    public static let green = Color(0, 255, 0)
    public static let blue = Color(0, 0, 255)
    public static let yellow = Color(255, 255, 0)
    public static let cyan = Color(0, 255, 255)
    public static let magenta = Color(255, 0, 255)
    public static let transparent = Color(0, 0, 0, 0)
}

