import Testing
import Metal
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - textWidth() の物差し

/// `textWidth()` が「1 字ずつの advance の合計」を返すことを確かめる（#802 の回帰テスト）。
///
/// `textWidth()` は文字を置く位置を決めるための物差しなので、
///
/// - **加法的**であること（語ごとに測って足しても、まとめて測っても同じ）
/// - **前後の空白を対称に数える**こと
///
/// が要る。光学バウンズを呼び出しごとに `ceil()` していた頃はどちらも成り立たなかった。
@Suite("Text width metrics", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TextWidthMetricsTests {

    /// 幅の比較に使う許容誤差。同じ advance を足すだけなので浮動小数の丸めしか出ない。
    private static let epsilon: Float = 0.01

    private func canvas(fontFamily: String, fontSize: Float) throws -> Canvas2D {
        let helper = try RenderTestHelper(width: 64, height: 64)
        helper.canvas.textFont(fontFamily)
        helper.canvas.textSize(fontSize)
        return helper.canvas
    }

    @Test("textWidth() は字数に対して加法的（等幅フォント）")
    func widthIsAdditiveForMonospace() throws {
        // Menlo は等幅なので、advance を足しているなら n 文字は 1 文字のちょうど n 倍になる。
        let canvas = try canvas(fontFamily: "Menlo", fontSize: 17)
        let unit = canvas.textWidth("i")
        #expect(unit > 0, "1 文字の幅が取れていない（\(unit)）")

        for n in [2, 4, 8, 16] {
            let repeated = canvas.textWidth(String(repeating: "i", count: n))
            #expect(abs(repeated - unit * Float(n)) < Self.epsilon,
                    "×\(n) が \(repeated) — 1 文字 \(unit) の \(n) 倍 \(unit * Float(n)) と食い違う")
        }
    }

    @Test("textWidth() は等幅フォントで字形によらず同じ幅を返す")
    func monospaceGlyphsShareAdvance() throws {
        let canvas = try canvas(fontFamily: "Menlo", fontSize: 17)
        let narrow = canvas.textWidth("i")
        let wide = canvas.textWidth("W")
        #expect(abs(narrow - wide) < Self.epsilon,
                "等幅なのに i=\(narrow) と W=\(wide) で幅が違う（墨面の広さを測っている）")
    }

    @Test("textWidth() は連結しても幅が合う（プロポーショナルフォント）")
    func widthIsAdditiveForProportional() throws {
        let canvas = try canvas(fontFamily: "Helvetica", fontSize: 17)
        let t = canvas.textWidth("T")
        let o = canvas.textWidth("o")
        let to = canvas.textWidth("To")
        #expect(abs(to - (t + o)) < Self.epsilon,
                "textWidth(\"To\")=\(to) が textWidth(\"T\")+textWidth(\"o\")=\(t + o) と食い違う")
    }

    @Test("textWidth() は前後の空白を対称に数える")
    func widthCountsWhitespaceOnBothSides() throws {
        let canvas = try canvas(fontFamily: "Helvetica", fontSize: 17)
        let space = canvas.textWidth(" ")
        let a = canvas.textWidth("A")
        #expect(space > 0, "空白の幅が 0（行末の空白を捨てる物差しになっている）")

        let trailing = canvas.textWidth("A ")
        let leading = canvas.textWidth(" A")
        #expect(abs(trailing - (a + space)) < Self.epsilon,
                "\"A \"=\(trailing) が \"A\"+\" \"=\(a + space) と食い違う（末尾の空白が落ちている）")
        #expect(abs(trailing - leading) < Self.epsilon,
                "\"A \"=\(trailing) と \" A\"=\(leading) が非対称")
    }

    @Test("textWidth() は空文字列で 0 を返す")
    func emptyStringHasZeroWidth() throws {
        let canvas = try canvas(fontFamily: "Helvetica", fontSize: 17)
        #expect(canvas.textWidth("") == 0)
    }
}

// MARK: - textAlign の基準幅

/// `textAlign(.center/.right)` が `textWidth()` と同じ幅で揃えることを確かめる（#803 の回帰テスト）。
///
/// 揃え幅は直接読めないので、同じ語を `.left` と `.right` で刷って**インクの左端の差**から
/// 逆算する。左サイドベアリング `lsb` は両方に等しく乗るので相殺され、フォント固有の定数を
/// テストへ持ち込まずに済む:
///
/// ```
/// .left  を xL に置くと ink 左端 = xL + lsb
/// .right を xR に置くと ink 左端 = xR - W + lsb   → W = xR + inkL(left) - xL - inkL(right)
/// ```
@Suite("Text align width", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TextAlignWidthTests {

    private static let canvasWidth = 320
    private static let canvasHeight = 120

    /// インクとみなす明るさ（背景は黒）。アンチエイリアスの裾を拾う程度に低く取る。
    private static let inkThreshold: Float = 0.004

    /// 語を 1 つだけ刷って、インクの左端（列番号）を返す。
    private func inkLeft(
        _ word: String, x: Float, align: TextAlignH, size: Float
    ) throws -> (left: Int, width: Float) {
        var helper = try RenderTestHelper(width: Self.canvasWidth, height: Self.canvasHeight)
        helper.setClearColor(r: 0, g: 0, b: 0)
        var measured: Float = 0
        try helper.render { canvas in
            canvas.fill(255)
            canvas.textFont("Helvetica")
            canvas.textSize(size)
            canvas.textAlign(align, .baseline)
            canvas.text(word, x, 80)
            measured = canvas.textWidth(word)
        }
        let columns = (0..<Self.canvasWidth).map {
            helper.averageColor(inRect: $0, y: 0, width: 1, height: Self.canvasHeight).r
        }
        guard let first = columns.indices.first(where: { columns[$0] > Self.inkThreshold }) else {
            Issue.record("\(align) で文字が描かれていない")
            return (0, measured)
        }
        return (first, measured)
    }

    @Test("textAlign(.right) は textWidth() と同じ幅で揃える", arguments: [15, 40] as [Float])
    func alignWidthMatchesTextWidth(size: Float) throws {
        let word = "Rgh"
        let xLeft: Float = 20
        let xRight: Float = 300

        let left = try inkLeft(word, x: xLeft, align: .left, size: size)
        let right = try inkLeft(word, x: xRight, align: .right, size: size)

        // 左サイドベアリングが相殺される形で揃え幅を逆算する
        let alignWidth = xRight + Float(left.left) - xLeft - Float(right.left)
        #expect(abs(alignWidth - left.width) <= 1.0,
                """
                揃えに使われた幅 \(alignWidth) が textWidth() \(left.width) と \
                \(alignWidth - left.width)px 食い違う（size \(size)）
                """)
    }

    @Test("textAlign(.center) は textWidth() の半分だけ左へ寄せる")
    func centerAlignUsesHalfTextWidth() throws {
        let word = "Rgh"
        let xLeft: Float = 20
        let xCenter: Float = 200

        let left = try inkLeft(word, x: xLeft, align: .left, size: 40)
        let center = try inkLeft(word, x: xCenter, align: .center, size: 40)

        // ink 左端 = xCenter - W/2 + lsb なので、W = 2 × (xCenter + lsb - inkL(center))
        // 逆算で 2 倍するぶん、画素へ丸めた誤差も 2 倍になるので許容は右揃えより広く取る。
        let alignWidth = 2 * (xCenter + Float(left.left) - xLeft - Float(center.left))
        #expect(abs(alignWidth - left.width) <= 1.5,
                "中央揃えの幅 \(alignWidth) が textWidth() \(left.width) と食い違う")
    }
}
