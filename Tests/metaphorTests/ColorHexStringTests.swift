import Testing
@testable import MetaphorCore

// MARK: - Color(hex: String) の綴り検証（Issue #799）

/// `Color(hex: String)` は `init?` なので「読めない綴り」は `nil` で伝わるのが約束です。
/// 桁数を見ずに `UInt32(_:radix:)` へ丸投げしていたころは、その約束が桁数の誤りだけをすり抜けて
/// **別の色として静かに通って**いました（`"#FFF"` が白ではなく青になる）。
///
/// 検査の要点は 3 つ:
///
/// - 受け付ける綴りは 3 / 6 / 8 桁だけ。それ以外は色を作らず `nil`
/// - 桁数が合っていても中身が ASCII の 16 進数字でなければ `nil`
///   （`UInt32(_:radix:)` は先頭の符号を受けるので `"+FFFFF"` は 6 文字で通ってしまう。
///   全角の `"ＦＦＦＦＦＦ"` は `isHexDigit` を通るので `isASCII` との併用が要る）
/// - 通った綴りは綴りどおりの色になる。とくに 8 桁のアルファ `00` が落ちない（Issue #870）
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

    // MARK: - 8 桁のアルファ 00（Issue #870）

    /// 8 桁のアルファは `00` も綴りどおりに読む。
    ///
    /// `init(hex: UInt32)` へ委譲していたころは、整数側が**値の大小**（`hex > 0xFFFFFF`）で
    /// 桁数を判別するため `0x00FFFFFF == 0xFFFFFF` が RGB 分岐に落ち、
    /// **アルファ `00` のときだけ** `1.0` に化けていました。`01` 以上なら正しく読まれるので、
    /// 完全透明を綴ったときだけ不透明になるという気付きにくい壊れ方です。
    @Test("8 桁のアルファ 00 は透明のまま（RGB は綴りどおり）")
    func zeroAlphaStaysTransparent() throws {
        #expect(bytes(try #require(Color(hex: "#00FFFFFF"))) == (0xFF, 0xFF, 0xFF, 0x00))
        #expect(bytes(try #require(Color(hex: "#00FF0000"))) == (0xFF, 0x00, 0x00, 0x00))
        #expect(bytes(try #require(Color(hex: "#000000FF"))) == (0x00, 0x00, 0xFF, 0x00))
    }

    /// 境界値: アルファ `00`（透明）と `01`（ほぼ透明）と `FF`（不透明）が隣り合って壊れない。
    @Test("アルファは 00 / 01 / FF が連続して読まれる")
    func alphaBoundaries() throws {
        #expect(try #require(Color(hex: "#00FFFFFF")).a == 0)
        #expect(bytes(try #require(Color(hex: "#01FFFFFF"))) == (0xFF, 0xFF, 0xFF, 0x01))
        #expect(try #require(Color(hex: "#FFFFFFFF")).a == 1)
    }

    /// アルファ `00` の 8 桁は、同じ RGB の 6 桁とは**別の色**でなければなりません
    /// （壊れていたころは両者が一致していました）。6 桁側は不透明のまま据え置きです。
    @Test("6 桁は不透明のまま。アルファ 00 の 8 桁とは一致しない")
    func sixDigitsRemainOpaque() throws {
        #expect(try #require(Color(hex: "#FFFFFF")).a == 1)
        #expect(Color(hex: "#00FFFFFF") != Color(hex: "#FFFFFF"))
        #expect(Color(hex: "#000000") == Color(hex: "#FF000000"))  // 6 桁の黒 = アルファ FF の黒
        #expect(Color(hex: "#00000000") == Color.clear)
    }

    /// 整数の `init(hex:)` は据え置きです（値からは桁数を判別できないため）。
    /// `0x00FFFFFF` は `0xFFFFFF` と同じ値で、透明な白を整数で綴る方法は原理的にありません。
    /// doc に書いた仕様どおりであることをここで固定し、文字列側の修正が整数側へ
    /// 波及していないことも示します。
    @Test("整数の init(hex:) は値の大小で判別するのでアルファ 00 を表現できない")
    func integerInitCannotExpressZeroAlpha() {
        #expect(Color(hex: 0x00FF_FFFF) == Color(hex: 0xFF_FFFF))
        #expect(Color(hex: 0x00FF_FFFF).a == 1)
        // 0xFFFFFF を超える値は AARRGGBB として読まれる（こちらは曖昧さがない）。
        #expect(bytes(Color(hex: 0x8000_0000)) == (0x00, 0x00, 0x00, 0x80))
    }
}
