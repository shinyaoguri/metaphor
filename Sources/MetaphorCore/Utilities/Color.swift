import Metal
import simd

/// 浮動小数点成分を持つ RGBA カラー。
///
/// 成分は 0.0 から 1.0 のスケールで表しますが、**この範囲に強制されるわけではありません**。
/// RGB、HSB、グレースケール、16進数形式からの初期化をサポートします。
///
/// ## 範囲外の成分
///
/// ``init(r:g:b:a:)`` と ``init(gray:alpha:)`` は引数をクランプせず、そのまま保持します。
/// 範囲外の成分は意図的にも作られます — `Color` は ``Interpolatable`` に準拠して線形外挿するため、
/// `easeOutBack` / `easeOutElastic` のようにオーバーシュートするイージングで `Tween<Color>` を回すと
/// 0.0...1.0 を外れた成分が生まれます。
///
/// 描画に使うと、成分は **描画時に 0.0...1.0 へ飽和** します。オフスクリーンのレンダーターゲットが
/// 正規化フォーマット（`bgra8Unorm`）で、GPU がフラグメント出力をブレンド**前**にクランプするためです。
/// 結果として:
///
/// - `a: 1.5` は `a: 1.0` と同じ絵になります（背景が引かれ過ぎることはありません）
/// - 負の成分を ``BlendMode/additive`` で重ねても背景は暗くなりません（0 として扱われます）
/// - 1.0 を超える輝度を保持する HDR 的な用途には使えません
/// - ``clearColor`` 経由の背景色も同じく飽和します
///
/// 成分を他の表現へ変換するとき（シェーダへのバインド、`UInt8` 化、CSS 文字列化など）は
/// 0.0...1.0 を不変条件として仮定せず、必要なら呼び出し側でクランプしてください。
public struct Color: Sendable, Equatable {
    /// 赤成分。0.0 から 1.0 のスケール（範囲外の値も保持されます）。
    public var r: Float
    /// 緑成分。0.0 から 1.0 のスケール（範囲外の値も保持されます）。
    public var g: Float
    /// 青成分。0.0 から 1.0 のスケール（範囲外の値も保持されます）。
    public var b: Float
    /// アルファ（不透明度）成分。0.0 から 1.0 のスケール（範囲外の値も保持されます）。
    public var a: Float

    // MARK: - RGB

    /// 0.0 から 1.0 のスケールの RGB 成分からカラーを作成します。
    ///
    /// 引数はクランプされません。範囲外の値はそのまま保持され、描画時に飽和します
    /// （``Color`` の「範囲外の成分」を参照）。
    ///
    /// - Parameters:
    ///   - r: 赤成分。
    ///   - g: 緑成分。
    ///   - b: 青成分。
    ///   - a: アルファ成分。デフォルトは 1.0（完全に不透明）。
    public init(r: Float, g: Float, b: Float, a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    // MARK: - Grayscale

    /// グレースケールカラーを作成します。0.0 が黒、1.0 が白。
    ///
    /// ``init(r:g:b:a:)`` と同じく引数はクランプされません。
    ///
    /// - Parameters:
    ///   - gray: グレースケール値。
    ///   - alpha: アルファ成分。デフォルトは 1.0（完全に不透明）。
    public init(gray: Float, alpha: Float = 1.0) {
        self.r = gray
        self.g = gray
        self.b = gray
        self.a = alpha
    }

    // MARK: - HSB

    /// 色相、彩度、明度の成分からカラーを作成します。
    ///
    /// RGB 系の初期化子と違い、`saturation` と `brightness` はここで 0.0...1.0 へクランプされます。
    /// 値域の約束ではなく、HSB→RGB 変換の前提を守るための防御です — 範囲外のまま計算すると
    /// 中間値（`p` / `q` / `t`）が意味を失い、色相ごとに不連続な色が出ます。
    /// `hue` は 0.0...1.0 を周期として巡回し、`alpha` はクランプされません。
    ///
    /// - Parameters:
    ///   - hue: 色相値。0.0 から 1.0 で一周し、範囲外の値は巡回します（1.25 は 0.25 と同じ）。
    ///   - saturation: 彩度値。0.0 から 1.0 の範囲へクランプされます。
    ///   - brightness: 明度値。0.0 から 1.0 の範囲へクランプされます。
    ///   - alpha: アルファ成分。デフォルトは 1.0（完全に不透明）。クランプされません。
    public init(hue: Float, saturation: Float, brightness: Float, alpha: Float = 1.0) {
        // NaN/∞ の hue は後段の Int(h) 変換でトラップするため 0 にフォールバック
        // （saturation/brightness は下のクランプで防御済み）。
        let safeHue: Float
        if hue.isFinite {
            safeHue = hue
        } else {
            metaphorWarning("Color(hue:saturation:brightness:) received non-finite hue (\(hue)); using 0")
            safeHue = 0
        }
        let h = ((safeHue.truncatingRemainder(dividingBy: 1.0)) + 1.0)
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

    /// 0xRRGGBB または 0xAARRGGBB 形式の整数16進数値からカラーを作成します。
    ///
    /// - Parameter hex: 16進数カラー値。0xFFFFFF より大きい値は AARRGGBB として解釈されます。
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

    /// "#RRGGBB" または "#AARRGGBB" 形式の16進数文字列からカラーを作成します。
    ///
    /// - Parameter hex: 16進数カラー文字列。"#" プレフィックスは省略可能。
    public init?(hex: String) {
        var str = hex
        if str.hasPrefix("#") { str.removeFirst() }
        guard let value = UInt32(str, radix: 16) else { return nil }
        self.init(hex: value)
    }

    // MARK: - SIMD Conversion

    /// カラーを (r, g, b, a) 順の `SIMD4<Float>` として返します。
    public var simd: SIMD4<Float> {
        SIMD4<Float>(r, g, b, a)
    }

    /// (r, g, b, a) として解釈される `SIMD4<Float>` ベクトルからカラーを作成します。
    ///
    /// - Parameter simd: カラー成分を含む SIMD ベクトル。
    public init(_ simd: SIMD4<Float>) {
        self.r = simd.x
        self.g = simd.y
        self.b = simd.z
        self.a = simd.w
    }

    // MARK: - Metal Conversion

    /// Metal レンダーパスで使用するための `MTLClearColor` としてカラーを返します。
    ///
    /// 成分はクランプせずそのまま渡します。範囲外の値はクリア時に 0.0...1.0 へ飽和します。
    public var clearColor: MTLClearColor {
        MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    // MARK: - Color Manipulation

    /// 指定されたアルファ値を持つ新しいカラーを返します。
    ///
    /// - Parameter alpha: 新しいアルファ値。
    /// - Returns: 指定されたアルファを持つこのカラーのコピー。
    public func withAlpha(_ alpha: Float) -> Color {
        Color(r: r, g: g, b: b, a: alpha)
    }

    /// このカラーと別のカラーの間を線形補間します。
    ///
    /// - Parameters:
    ///   - other: 目標カラー。
    ///   - t: 補間係数。0...1 の範囲にクランプされます。
    /// - Returns: 補間されたカラー。
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

    /// 純粋な黒。
    public static let black = Color(gray: 0)
    /// 純粋な白。
    public static let white = Color(gray: 1)
    /// 純粋な赤。
    public static let red = Color(r: 1, g: 0, b: 0)
    /// 純粋な緑。
    public static let green = Color(r: 0, g: 1, b: 0)
    /// 純粋な青。
    public static let blue = Color(r: 0, g: 0, b: 1)
    /// 純粋な黄。
    public static let yellow = Color(r: 1, g: 1, b: 0)
    /// 純粋なシアン。
    public static let cyan = Color(r: 0, g: 1, b: 1)
    /// 純粋なマゼンタ。
    public static let magenta = Color(r: 1, g: 0, b: 1)
    /// オレンジ。
    public static let orange = Color(r: 1, g: 0.6, b: 0)
    /// 完全に透明な黒。
    public static let clear = Color(r: 0, g: 0, b: 0, a: 0)
}

// MARK: - Global Color Functions

/// 2つのカラーの間を線形補間します。
///
/// - Parameters:
///   - c1: 開始カラー。
///   - c2: 終了カラー。
///   - t: 補間係数。
/// - Returns: 補間されたカラー。
public func lerpColor(_ c1: Color, _ c2: Color, _ t: Float) -> Color {
    c1.lerp(to: c2, t: t)
}

// MARK: - Color Space

/// カラー解釈に使用されるカラースペースを定義します。
public enum ColorSpace: Sendable {
    /// 赤、緑、青のカラースペース。
    case rgb
    /// 色相、彩度、明度のカラースペース。
    case hsb
}

// MARK: - Color Mode Config

/// `colorMode()` 関数の設定を保持します。
///
/// ユーザーが指定した値を正規化し、``Color`` インスタンスに変換します。
public struct ColorModeConfig: Sendable, Equatable {
    /// アクティブなカラースペース。
    public var space: ColorSpace = .rgb
    /// 1番目の成分（赤または色相）の最大値。
    public var max1: Float = 255.0
    /// 2番目の成分（緑または彩度）の最大値。
    public var max2: Float = 255.0
    /// 3番目の成分（青または明度）の最大値。
    public var max3: Float = 255.0
    /// アルファ成分の最大値。
    public var maxAlpha: Float = 255.0

    /// 3つの成分値とオプションのアルファをカラーに変換します。
    ///
    /// 各成分を対応する最大値で割って正規化するだけで、上限は強制しません。
    /// 既定の `max1 = 255` に対する `fill(300)` のように最大値を超える入力を渡すと、
    /// ``ColorSpace/rgb`` では 0.0...1.0 を外れた成分を持つ ``Color`` になります（描画時に飽和します）。
    /// ``ColorSpace/hsb`` では ``Color/init(hue:saturation:brightness:alpha:)`` が
    /// 彩度・明度をクランプし、色相は巡回します。
    ///
    /// - Parameters:
    ///   - v1: 1番目の成分値（赤または色相）。
    ///   - v2: 2番目の成分値（緑または彩度）。
    ///   - v3: 3番目の成分値（青または明度）。
    ///   - alpha: アルファ値。`nil` の場合は `maxAlpha` がデフォルト値となります。
    /// - Returns: 正規化された成分を持つカラー。
    public func toColor(_ v1: Float, _ v2: Float, _ v3: Float, _ alpha: Float? = nil) -> Color {
        let nA = (alpha ?? maxAlpha) / maxAlpha
        switch space {
        case .rgb:
            return Color(r: v1 / max1, g: v2 / max2, b: v3 / max3, a: nA)
        case .hsb:
            return Color(hue: v1 / max1, saturation: v2 / max2, brightness: v3 / max3, alpha: nA)
        }
    }

    /// グレースケール値とオプションのアルファをカラーに変換します。
    ///
    /// ``toColor(_:_:_:_:)`` と同じく `max1` で割るだけで、上限は強制しません。
    ///
    /// - Parameters:
    ///   - gray: グレースケール値。
    ///   - alpha: アルファ値。`nil` の場合は `maxAlpha` がデフォルト値となります。
    /// - Returns: 正規化された成分を持つグレースケールカラー。
    public func toGray(_ gray: Float, _ alpha: Float? = nil) -> Color {
        let nA = (alpha ?? maxAlpha) / maxAlpha
        return Color(gray: gray / max1, alpha: nA)
    }
}
