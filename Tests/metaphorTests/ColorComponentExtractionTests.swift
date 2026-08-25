import Testing

@testable import MetaphorCore

// MARK: - 色成分の抽出（Issue #811）

/// `Color` は長らく HSB → RGB の一方向しか持たず、`hue()` / `saturation()` / `brightness()` /
/// `alpha()` / `red()` / `green()` / `blue()` に相当する抽出手段がありませんでした。
///
/// この検査盤が固定するのは 4 点です:
///
/// - **往復**: `Color(hue:saturation:brightness:alpha:)` と抽出は互いの逆関数で、両向きに閉じる
/// - **レンジ**: 戻り値は 0.0...1.0 で、`colorMode()` に従わない（決定の根拠は Issue #811 の
///   コメント。移植時は呼び出し側で `hue(c) * 360` のように掛ける）
/// - **境界**: 無彩色・彩度 0・黒の色相は 0、色相は 1.0 に到達しない、alpha 0 でも成分は読める
/// - **別名**: free function 7 本は `Color` のプロパティと同じ値を返す（真実を 2 本にしない）
@Suite("Color component extraction")
struct ColorComponentExtractionTests {

    /// 往復に許す誤差。変換は Float の除算 2 回ぶんなので 1e-5 で十分に厳しく、
    /// セクタ境界（`maxC` が 2 成分で並ぶ点）でも余裕があります。
    private static let tolerance: Float = 1e-5

    private func expectClose(
        _ actual: Float, _ expected: Float, _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            abs(actual - expected) < Self.tolerance,
            "\(label): got \(actual), expected \(expected)",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - 往復

    /// 代表色 + 中間色を RGB → HSB → RGB で回して元に戻ることを見ます。
    @Test(
        "RGB → HSB → RGB で元の色に戻る",
        arguments: [
            Color(r: 1, g: 0, b: 0),
            Color(r: 0, g: 1, b: 0),
            Color(r: 0, g: 0, b: 1),
            Color(r: 1, g: 1, b: 0),
            Color(r: 0, g: 1, b: 1),
            Color(r: 1, g: 0, b: 1),
            Color(r: 1, g: 1, b: 1),
            Color(r: 0, g: 0, b: 0),
            Color(r: 0.5, g: 0.25, b: 0.75),
            Color(r: 0.2, g: 0.9, b: 0.4, alpha: 0.3),
            Color(r: 0.13, g: 0.13, b: 0.42),
            Color(hex: 0xFF8000),
        ]
    )
    func rgbRoundTrip(original: Color) {
        let restored = Color(
            hue: original.hue,
            saturation: original.saturation,
            brightness: original.brightness,
            alpha: original.a
        )
        expectClose(restored.r, original.r, "r")
        expectClose(restored.g, original.g, "g")
        expectClose(restored.b, original.b, "b")
        expectClose(restored.a, original.a, "a")
    }

    /// 逆向き。色相を 0.0..<1.0 で刻み、HSB → RGB → HSB で戻ることを見ます。
    @Test("HSB → RGB → HSB で元の成分に戻る")
    func hsbRoundTrip() {
        for step in 0..<24 {
            let h = Float(step) / 24.0
            for s in [Float(0.35), 1.0] {
                for v in [Float(0.4), 1.0] {
                    let c = Color(hue: h, saturation: s, brightness: v)
                    expectClose(c.hue, h, "hue(h=\(h) s=\(s) v=\(v))")
                    expectClose(c.saturation, s, "saturation(h=\(h) s=\(s) v=\(v))")
                    expectClose(c.brightness, v, "brightness(h=\(h) s=\(s) v=\(v))")
                }
            }
        }
    }

    // MARK: - 既知の値

    @Test(
        "純色の色相は 6 分割のちょうど境界",
        arguments: [
            (Color(r: 1, g: 0, b: 0), Float(0.0)),
            (Color(r: 1, g: 1, b: 0), Float(1.0 / 6.0)),
            (Color(r: 0, g: 1, b: 0), Float(2.0 / 6.0)),
            (Color(r: 0, g: 1, b: 1), Float(3.0 / 6.0)),
            (Color(r: 0, g: 0, b: 1), Float(4.0 / 6.0)),
            (Color(r: 1, g: 0, b: 1), Float(5.0 / 6.0)),
        ]
    )
    func pureHues(color: Color, expected: Float) {
        expectClose(color.hue, expected, "hue")
        expectClose(color.saturation, 1.0, "saturation")
        expectClose(color.brightness, 1.0, "brightness")
    }

    /// `brightness` は HSB の value（3 成分の最大）であって知覚輝度ではありません。
    /// 純青と白がどちらも 1.0 になることをここで固定します。
    @Test("brightness は最大成分であって知覚輝度ではない")
    func brightnessIsValueNotLuminance() {
        expectClose(Color.blue.brightness, 1.0, "blue")
        expectClose(Color.white.brightness, 1.0, "white")
    }

    // MARK: - 境界値

    /// 無彩色の色相は数学的に未定義。Processing（`java.awt.Color.RGBtoHSB`）と同じく 0 を返します。
    @Test("グレースケールは色相 0・彩度 0・brightness = 明度", arguments: [Float(0.0), 0.25, 1.0])
    func grayscale(gray: Float) {
        let c = Color(gray: gray)
        expectClose(c.hue, 0, "hue")
        expectClose(c.saturation, 0, "saturation")
        expectClose(c.brightness, gray, "brightness")
    }

    /// 黒は `maxC == 0` で彩度の分母が 0 になる特異点。NaN を返さないことを見ます。
    @Test("黒は彩度 0（0 除算にならない）")
    func blackHasZeroSaturation() {
        let c = Color.black
        #expect(c.saturation.isFinite)
        expectClose(c.saturation, 0, "saturation")
        expectClose(c.brightness, 0, "brightness")
        expectClose(c.hue, 0, "hue")
    }

    /// 彩度 0 の色は、どんな色相で作っても色相 0 として読み戻ります（情報が落ちる方向は片道）。
    @Test("彩度 0 で作った色は色相を保持しない")
    func zeroSaturationLosesHue() {
        let c = Color(hue: 0.75, saturation: 0, brightness: 0.6)
        expectClose(c.hue, 0, "hue")
        expectClose(c.saturation, 0, "saturation")
        expectClose(c.brightness, 0.6, "brightness")
    }

    /// 色相は 1 周を 0.0..<1.0 で表すので、赤の手前まで来ても 1.0 には到達しません。
    /// 「純赤が 0 か 1 か」で分岐するコードを書かせないための固定です。
    @Test("色相は 1.0 に到達しない（赤は 0.0 側に折り返す）")
    func hueNeverReachesOne() {
        // 赤の直前（青がごくわずか）。色相は 1.0 に限りなく近いが 1.0 未満。
        let almostRed = Color(r: 1, g: 0, b: 0.001)
        #expect(almostRed.hue < 1.0, "hue=\(almostRed.hue)")
        #expect(almostRed.hue > 0.99, "hue=\(almostRed.hue)")

        // 純赤は折り返して 0.0。
        expectClose(Color(r: 1, g: 0, b: 0).hue, 0, "pure red hue")

        // 1 周ぶん足した色相で作っても、読み戻しは 0.0..<1.0 に畳まれる。
        for h in [Float(1.25), 2.25, -0.75] {
            let c = Color(hue: h, saturation: 1, brightness: 1)
            #expect(c.hue >= 0 && c.hue < 1.0, "hue=\(h) → \(c.hue)")
            expectClose(c.hue, 0.25, "wrapped hue(\(h))")
        }
    }

    /// alpha が 0 でも色成分は読めます（透明＝黒ではない）。
    @Test("alpha 0 でも色成分は失われない")
    func fullyTransparentKeepsComponents() {
        let c = Color(r: 0.2, g: 0.4, b: 0.8, alpha: 0)
        expectClose(alpha(c), 0, "alpha")
        expectClose(red(c), 0.2, "red")
        expectClose(green(c), 0.4, "green")
        expectClose(blue(c), 0.8, "blue")
        expectClose(c.brightness, 0.8, "brightness")
        #expect(c.hue > 0.5 && c.hue < 0.7, "hue=\(c.hue)")
    }

    /// 範囲外成分の扱いの非対称をここで固定します。
    /// HSB 側は変換の前提を守るため 0...1 へクランプ、RGB / alpha 側は `.r` などの素通し。
    @Test("HSB 側は範囲外成分をクランプし、RGB / alpha 側は素通しする")
    func outOfRangeComponents() {
        let over = Color(r: 1.5, g: 0, b: 0, alpha: 1.5)
        expectClose(over.brightness, 1.0, "brightness clamps")
        expectClose(over.saturation, 1.0, "saturation")
        expectClose(over.hue, 0, "hue")
        // 抽出側は Color のプロパティをそのまま返す（クランプしない）
        #expect(red(over) == 1.5)
        #expect(alpha(over) == 1.5)

        let under = Color(r: -0.5, g: 0.5, b: 0)
        expectClose(under.brightness, 0.5, "brightness")
        #expect(red(under) == -0.5)
    }

    /// 読み出しアクセサは決して落ちない（ADR-0005 / #356）。非有限成分は 0 として読みます。
    @Test(
        "非有限成分でも落ちず、有限値を返す", arguments: [Float.nan, .infinity, -.infinity])
    func nonFiniteComponents(bad: Float) {
        let c = Color(r: bad, g: 0.5, b: 0.25)
        #expect(c.hue.isFinite, "hue=\(c.hue)")
        #expect(c.saturation.isFinite, "saturation=\(c.saturation)")
        #expect(c.brightness.isFinite, "brightness=\(c.brightness)")
        // r は 0 として読まれるので、最大成分は g = 0.5
        expectClose(c.brightness, 0.5, "brightness")
    }

    // MARK: - free function は別名

    @Test("free function 7 本は Color のプロパティと同じ値を返す")
    func freeFunctionsMatchProperties() {
        let c = Color(r: 0.3, g: 0.6, b: 0.9, alpha: 0.45)
        #expect(hue(c) == c.hue)
        #expect(saturation(c) == c.saturation)
        #expect(brightness(c) == c.brightness)
        #expect(red(c) == c.r)
        #expect(green(c) == c.g)
        #expect(blue(c) == c.b)
        #expect(alpha(c) == c.a)
    }

    // MARK: - colorMode に従わない

    /// 決定の実体。`colorMode(.hsb, 360, 100, 100)` 相当の設定で作った色でも、抽出は 0.0...1.0 を
    /// 返します。Processing のレンジへ戻すのは呼び出し側の掛け算です。
    @Test("抽出は colorMode の設定に影響されない")
    func extractionIgnoresColorMode() {
        let hsb360 = ColorModeConfig(
            space: .hsb, max1: 360, max2: 100, max3: 100, maxAlpha: 100)
        let c = hsb360.toColor(180, 100, 100, 100)

        // Processing なら hue(c) == 180 になるところを、metaphor は 0.5 を返す
        expectClose(hue(c), 0.5, "hue")
        expectClose(saturation(c), 1.0, "saturation")
        expectClose(brightness(c), 1.0, "brightness")
        expectClose(alpha(c), 1.0, "alpha")

        // doc に書いた移植レシピが成り立つこと
        expectClose(hue(c) * 360, 180, "hue(c) * 360")
        expectClose(saturation(c) * 100, 100, "saturation(c) * 100")

        // RGB 側の設定を変えても同じ（255 レンジで作った赤も red() は 1.0）
        let rgb255 = ColorModeConfig(space: .rgb, max1: 255, max2: 255, max3: 255, maxAlpha: 255)
        let redish = rgb255.toColor(255, 0, 0, 255)
        expectClose(red(redish), 1.0, "red")
        expectClose(red(redish) * 255, 255, "red(c) * 255")
    }
}
