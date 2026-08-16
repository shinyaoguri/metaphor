import Testing
@testable import MetaphorCore

// MARK: - Color(hex: String) の綴り検証（Issue #799）

/// `Color(hex: String)` は `init?` なので「読めない綴り」は `nil` で伝わるのが約束です。
/// 桁数を見ずに `UInt32(_:radix:)` へ丸投げしていたころは、その約束が桁数の誤りだけをすり抜けて
/// **別の色として静かに通って**いました（`"#FFF"` が白ではなく青になる）。
///
/// 検査の要点は 2 つ:
///
/// - 受け付ける綴りは 3 / 6 / 8 桁だけ。それ以外は色を作らず `nil`
/// - 桁数が合っていても中身が ASCII の 16 進数字でなければ `nil`
///   （`UInt32(_:radix:)` は先頭の符号を受けるので `"+FFFFF"` は 6 文字で通ってしまう。
///   全角の `"ＦＦＦＦＦＦ"` は `isHexDigit` を通るので `isASCII` との併用が要る）
@Suite("Color hex string")
struct ColorHexStringTests {

    /// 成分（0.0...1.0）を 8bit へ戻して比べます。丸め方に依らない照合にするためです。
    private func bytes(_ c: Color) -> (UInt8, UInt8, UInt8, UInt8) {
        (
            UInt8((c.r * 255).rounded()),
            UInt8((c.g * 255).rounded()),
            UInt8((c.b * 255).rounded()),
            UInt8((c.a * 255).rounded())
        )
    }

    // MARK: - 受け付ける綴り

    @Test("6 桁は RRGGBB として読む（# は省略可）", arguments: ["#FF8000", "FF8000", "#ff8000"])
    func sixDigits(spelling: String) throws {
        let c = try #require(Color(hex: spelling))
        #expect(bytes(c) == (0xFF, 0x80, 0x00, 0xFF))
    }

    @Test("8 桁は AARRGGBB として読む")
    func eightDigits() throws {
        let c = try #require(Color(hex: "#80FF0000"))
        #expect(bytes(c) == (0xFF, 0x00, 0x00, 0x80))
    }

    @Test("3 桁は CSS の短縮形として展開する（#FFF は白）")
    func threeDigitsExpand() throws {
        let white = try #require(Color(hex: "#FFF"))
        #expect(bytes(white) == (0xFF, 0xFF, 0xFF, 0xFF))

        // 展開は各桁の 2 倍化。0AF → 00AAFF であって 000AF... ではない。
        let mixed = try #require(Color(hex: "#0AF"))
        #expect(bytes(mixed) == (0x00, 0xAA, 0xFF, 0xFF))

        // 6 桁で綴った同じ色と一致する
        #expect(Color(hex: "#f00") == Color(hex: "#FF0000"))
    }

    @Test("大文字小文字は混ぜてよい")
    func mixedCase() throws {
        #expect(Color(hex: "#AbCdEf") == Color(hex: "#abcdef"))
        #expect(Color(hex: "#ABCDEF") == Color(hex: "#abcdef"))
    }

    // MARK: - 受け付けない綴り（桁数）

    /// 3 / 6 / 8 以外はすべて `nil`。とくに **4 桁は受けません** —
    /// このライブラリの 8 桁は AARRGGBB（CSS の RRGGBBAA と逆順）なので、
    /// 4 桁短縮形は ARGB とも RGBA とも読め、どちらに決めても他方の綴りが黙って別の色になります。
    /// それはこの Issue が直そうとしている失敗の形そのものです。
    @Test(
        "3 / 6 / 8 桁以外は nil",
        arguments: ["#F", "#FF", "#1234", "#12345", "#1234567", "#123456789", "#", ""]
    )
    func wrongDigitCountIsNil(spelling: String) {
        #expect(Color(hex: spelling) == nil)
    }

    @Test("4 桁は ARGB とも RGBA とも読めるので受けない")
    func fourDigitsRejected() {
        #expect(Color(hex: "#F00A") == nil)
        #expect(Color(hex: "#AF00") == nil)
    }

    // MARK: - 受け付けない綴り（中身）

    /// 桁数が合っていても、ASCII の 16 進数字以外が混じっていれば `nil`。
    @Test(
        "桁数が合っていても 16 進数字でなければ nil",
        arguments: [
            "#GGGGGG",       // 16 進の範囲外
            "+FFFFF",        // UInt32(_:radix:) が受ける先頭の符号（6 文字なので桁数だけでは通る）
            "-FFFFF",
            " FFFFF",        // 空白
            "ＦＦＦＦＦＦ",    // 全角（isHexDigit は true になるが ASCII ではない）
            "0x1234",        // 0x プレフィックス付き
            "FF FFFF",       // 途中の空白（7 文字）
            "not a color"
        ]
    )
    func nonHexDigitsAreNil(spelling: String) {
        #expect(Color(hex: spelling) == nil)
    }

    @Test("# を外した中身で判定する（'#' だけ・'#' 込みの桁数ではない）")
    func hashIsStrippedBeforeCounting() {
        // "#FF8000" は # を除いて 6 桁なので通る。"#FF800" は 5 桁なので通らない。
        #expect(Color(hex: "#FF8000") != nil)
        #expect(Color(hex: "#FF800") == nil)
        // 2 つ目以降の # は 16 進数字ではないので nil
        #expect(Color(hex: "##FF8000") == nil)
    }
}
