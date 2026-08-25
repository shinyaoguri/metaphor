import CoreText
import Foundation
import Metal
import MetaphorTestSupport
import Testing

@testable import MetaphorCore

// MARK: - textWrap()

/// `textWrap()` が矩形版 `text()` の折り返し規則をどう変えるかを固定する（Issue #1165）。
///
/// ## なぜこのテストがあるか
///
/// 折り返しは `NSMutableParagraphStyle.lineBreakMode` **1 行**で決まる。その 1 行が
/// 落ちても消えても、コンパイルエラーにも警告にもならず**絵だけが黙って変わる**
/// （既定値が `.byWordWrapping` なので、指定が丸ごと消えると `.char` が `.word` に戻る）。
/// しかも `TextRenderer` はレンダリング結果をキャッシュするので、キャッシュキーに
/// 折り方を入れ忘れると「1 回目に描いた規則のまま 2 回目も描く」形で壊れる。
///
/// そのため**行がどこで折れたか**を実際の絵から測る。
///
/// ## フォントの選び方
///
/// システムフォントの字幅に依存しないよう、リポジトリ同梱の `SpaceMono-Regular.ttf`
/// （等幅）をプロセスへ登録して使う（`TextStyleResolutionTests` と同じフィクスチャ）。
/// 等幅なら「箱に何文字入るか」を `textWidth()` から一意に決められる。
@Suite("Text wrap", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TextWrapTests {

    private static let canvasWidth = 260
    private static let canvasHeight = 160
    private static let fontSize: Float = 16
    private static let leading: Float = 20
    private static let boxOrigin: Float = 10

    /// 短い語のあとに、1 行に収まらない長い語が続く文字列。
    ///
    /// `.word` は長い語を丸ごと次の行へ送るので 1 行目が `ab` だけになり、`.char` は
    /// 1 行目を箱の右端まで埋める。**1 行目のインク幅**という 1 つの数字で両者が分かれる。
    private static let sample = "ab cdefghijklmno"

    /// インクとみなす明るさ（`MultilineTextTests` と同じ閾値）。
    private static let inkThreshold: Float = 0.004

    // MARK: - ヘルパー

    /// テスト用の等幅フォントを載せたキャンバスで 1 フレーム描く。
    ///
    /// - Returns: 描き終えたヘルパーと、そのとき使った箱の幅。
    private func render(
        boxWidthInCharacters: Int = 10,
        _ draw: (Canvas2D, _ boxWidth: Float) -> Void
    ) throws -> (helper: RenderTestHelper, boxWidth: Float) {
        let font = try TextStyleResolutionTests.registerSingleFaceFixture()
        var helper = try RenderTestHelper(width: Self.canvasWidth, height: Self.canvasHeight)
        helper.setClearColor(r: 0, g: 0, b: 0)
        helper.canvas.textFont(font)
        helper.canvas.textSize(Self.fontSize)
        helper.canvas.textLeading(Self.leading)
        helper.canvas.textAlign(.left, .top)

        // 等幅なので「n 文字ぶんの advance」がそのまま「n 文字入る箱」になる。
        // 端数で 1 文字ぶれないよう、ごく僅かに広げておく。
        let boxWidth = helper.canvas.textWidth(
            String(repeating: "a", count: boxWidthInCharacters)) + 1

        try helper.render { canvas in
            canvas.fill(255)
            draw(canvas, boxWidth)
        }
        return (helper, boxWidth)
    }

    /// 指定した行範囲・列範囲のインク量（列ごと、左から順）。
    private func columnInk(
        _ helper: RenderTestHelper, rows: Range<Int>, columns: Range<Int>
    ) -> [Float] {
        columns.map {
            helper.averageColor(inRect: $0, y: rows.lowerBound, width: 1, height: rows.count).r
        }
    }

    /// 行ごとのインク量（上から順）。
    private func rowInk(_ helper: RenderTestHelper) -> [Float] {
        (0..<Self.canvasHeight).map {
            helper.averageColor(inRect: 0, y: $0, width: Self.canvasWidth, height: 1).r
        }
    }

    /// 連続して閾値を超える区間を上から順に返す（帯の数 = 描かれた行数）。
    private func inkBands(_ profile: [Float]) -> [(first: Int, last: Int)] {
        var bands: [(first: Int, last: Int)] = []
        var start: Int?
        for i in profile.indices {
            if profile[i] > Self.inkThreshold {
                if start == nil { start = i }
            } else if let s = start {
                bands.append((s, i - 1))
                start = nil
            }
        }
        if let s = start { bands.append((s, profile.count - 1)) }
        return bands
    }

    /// インクのある範囲（最初と最後の位置）。インクが無ければ nil。
    private func inkExtent(_ profile: [Float]) -> (first: Int, last: Int)? {
        let inked = profile.indices.filter { profile[$0] > Self.inkThreshold }
        guard let first = inked.first, let last = inked.last else { return nil }
        return (first, last)
    }

    /// 1 行目のインク幅（px）。折り方の違いはここに一番はっきり出る。
    private func firstLineInkWidth(
        _ helper: RenderTestHelper, columns: Range<Int>
    ) throws -> Int {
        let bands = inkBands(rowInk(helper))
        let first = try #require(bands.first, "文字が 1 行も描かれていない")
        let profile = columnInk(helper, rows: first.first..<(first.last + 1), columns: columns)
        let extent = try #require(inkExtent(profile), "1 行目にインクが無い")
        return extent.last - extent.first + 1
    }

    // MARK: - 正常系

    @Test(".char は語の途中で折り、1 行目を箱の右端まで埋める")
    func charWrapFillsTheFirstLine() throws {
        let word = try render { canvas, boxWidth in
            canvas.textWrap(.word)
            canvas.text(Self.sample, Self.boxOrigin, Self.boxOrigin, boxWidth, 120)
        }
        let char = try render { canvas, boxWidth in
            canvas.textWrap(.char)
            canvas.text(Self.sample, Self.boxOrigin, Self.boxOrigin, boxWidth, 120)
        }

        let columns = 0..<Self.canvasWidth
        let wordWidth = try firstLineInkWidth(word.helper, columns: columns)
        let charWidth = try firstLineInkWidth(char.helper, columns: columns)

        // `.word` の 1 行目は "ab" の 2 文字ぶん、`.char` は 10 文字ぶん。
        #expect(
            charWidth > wordWidth * 3,
            ".char が語の途中で折っていない（1 行目のインク幅 .word \(wordWidth)px / .char \(charWidth)px）"
        )
        #expect(
            Float(charWidth) > char.boxWidth * 0.8,
            ".char の 1 行目が箱の右端まで埋まっていない（\(charWidth)px / 箱 \(char.boxWidth)px）")
    }

    @Test("既定は .word（textWrap() を呼ばないときと同じ絵）")
    func wordIsTheDefault() throws {
        let implicit = try render { canvas, boxWidth in
            canvas.text(Self.sample, Self.boxOrigin, Self.boxOrigin, boxWidth, 120)
        }
        let explicit = try render { canvas, boxWidth in
            canvas.textWrap(.word)
            canvas.text(Self.sample, Self.boxOrigin, Self.boxOrigin, boxWidth, 120)
        }

        var mismatches = 0
        for y in 0..<Self.canvasHeight {
            for x in 0..<Self.canvasWidth {
                let a = implicit.helper.readPixel(x: x, y: y)
                let b = explicit.helper.readPixel(x: x, y: y)
                if a.r != b.r || a.g != b.g || a.b != b.b { mismatches += 1 }
            }
        }
        #expect(mismatches == 0, "既定が .word からずれている（\(mismatches) px 違う）")

        let canvas = try MetalTestHelper.canvas2D(width: 16, height: 16)
        #expect(canvas.currentTextWrap == .word, "初期値が .word ではない")
    }

    @Test("同じフレームで規則を切り替えても、キャッシュした絵が混ざらない")
    func wrapModeIsPartOfTheCacheKey() throws {
        // 同じ文字列・同じ箱の大きさを 1 フレームに 2 回描く。折り方がキャッシュキーに
        // 入っていないと、2 つ目は 1 つ目のテクスチャを引いて同じ絵になる。
        let rendered = try render { canvas, boxWidth in
            canvas.textWrap(.word)
            canvas.text(Self.sample, Self.boxOrigin, Self.boxOrigin, boxWidth, 120)
            canvas.textWrap(.char)
            canvas.text(
                Self.sample, Float(Self.canvasWidth / 2) + Self.boxOrigin, Self.boxOrigin,
                boxWidth, 120)
        }

        let left = try firstLineInkWidth(rendered.helper, columns: 0..<(Self.canvasWidth / 2))
        let right = try firstLineInkWidth(
            rendered.helper, columns: (Self.canvasWidth / 2)..<Self.canvasWidth)
        #expect(
            right > left * 3,
            "2 つ目が 1 つ目のキャッシュを引いている（1 行目のインク幅 左 \(left)px / 右 \(right)px）")
    }

    @Test("textWrap() は 3 引数の text() には効かない")
    func wrapDoesNotAffectThePointForm() throws {
        func draw(_ mode: TextWrap) throws -> RenderTestHelper {
            try render { canvas, _ in
                canvas.textWrap(mode)
                canvas.text(Self.sample, Self.boxOrigin, Self.boxOrigin)
            }.helper
        }

        let word = try draw(.word)
        let char = try draw(.char)
        var mismatches = 0
        for y in 0..<Self.canvasHeight {
            for x in 0..<Self.canvasWidth {
                let a = word.readPixel(x: x, y: y)
                let b = char.readPixel(x: x, y: y)
                if a.r != b.r || a.g != b.g || a.b != b.b { mismatches += 1 }
            }
        }
        #expect(mismatches == 0, "幅を取らない text() が textWrap() に反応している（\(mismatches) px）")
    }

    // MARK: - 境界値

    @Test("1 文字も入らない幅でも 1 文字ずつ折って描く", arguments: [TextWrap.word, .char])
    func narrowerThanOneGlyph(mode: TextWrap) throws {
        let rendered = try render(boxWidthInCharacters: 1) { canvas, boxWidth in
            canvas.textWrap(mode)
            // 箱の幅を 1 文字ぶんよりさらに狭くする。
            canvas.text("abc", Self.boxOrigin, Self.boxOrigin, boxWidth * 0.4, 140)
        }
        let bands = inkBands(rowInk(rendered.helper))
        #expect(bands.count >= 2, "\(mode) で折り返せていない（インクの帯 \(bands.count) 本）")
    }

    @Test("空文字列は何も描かない", arguments: [TextWrap.word, .char])
    func emptyStringDrawsNothing(mode: TextWrap) throws {
        let rendered = try render { canvas, boxWidth in
            canvas.textWrap(mode)
            canvas.text("", Self.boxOrigin, Self.boxOrigin, boxWidth, 120)
        }
        #expect(
            inkBands(rowInk(rendered.helper)).isEmpty,
            "空文字列で何かが描かれている（\(mode)）")
    }

    // MARK: - 状態

    @Test("textWrap は push() / pop() で保存・復元される")
    func wrapIsSavedByPushPop() throws {
        let canvas = try MetalTestHelper.canvas2D(width: 16, height: 16)
        canvas.textWrap(.char)
        canvas.push()
        canvas.textWrap(.word)
        #expect(canvas.currentTextWrap == .word)
        canvas.pop()
        #expect(canvas.currentTextWrap == .char, "pop() で折り返し規則が戻っていない")
    }

    @Test("textWrap は pushStyle() / popStyle() で保存・復元される")
    func wrapIsSavedByPushStyle() throws {
        let canvas = try MetalTestHelper.canvas2D(width: 16, height: 16)
        canvas.textWrap(.char)
        canvas.pushStyle()
        canvas.textWrap(.word)
        canvas.popStyle()
        #expect(canvas.currentTextWrap == .char, "popStyle() で折り返し規則が戻っていない")
    }
}

// MARK: - textBounds()

/// `textBounds()` が返す矩形を固定する（Issue #1165）。
///
/// ## なぜこのテストがあるか
///
/// 物差しは #802 / #803 で **advance の合計**へ統一済みで、`textWidth()` の doc も
/// `textAlign()` の実装（`textBaselineOrigin`）もその 1 本に乗っている。`textBounds()`
/// だけが墨面へ寄ると、**`textBounds()` で測って `textAlign()` で置いた文字がずれる**。
/// 数値どうしの恒等式は目視では気付けないので、ここで固定する。
@Suite("Text bounds", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TextBoundsTests {

    private func canvas(size: Float = 32, font: String = "Helvetica") throws -> Canvas2D {
        let canvas = try MetalTestHelper.canvas2D(width: 64, height: 64)
        canvas.textFont(font)
        canvas.textSize(size)
        return canvas
    }

    // MARK: - textWidth() との一致

    @Test(
        "幅は textWidth() と一致する",
        arguments: [
            ("metaphor", "Helvetica", Float(32)),
            ("fff", "Helvetica", 32),
            ("iiiiii", "Menlo", 12),
            ("Wg", "Menlo", 64),
            (" leading and trailing ", "Helvetica", 20),
        ] as [(String, String, Float)])
    func widthMatchesTextWidth(string: String, font: String, size: Float) throws {
        let canvas = try canvas(size: size, font: font)

        #expect(canvas.textBounds(string, 0, 0).width == canvas.textWidth(string))
    }

    @Test("高さは 1 行なら ascent + descent")
    func heightIsAscentPlusDescent() throws {
        let canvas = try canvas()

        let bounds = canvas.textBounds("metaphor", 10, 20)

        #expect(bounds.height == canvas.textAscent() + canvas.textDescent())
    }

    @Test("高さは字形ではなくフォントで決まる（\"x\" と \"X\" で同じ）")
    func heightDoesNotFollowTheGlyph() throws {
        let canvas = try canvas()

        #expect(canvas.textBounds("x", 0, 0).height == canvas.textBounds("X", 0, 0).height)
    }

    // MARK: - 複数行

    @Test("改行のぶんだけ leading が高さに積まれる")
    func newlinesAddLeading() throws {
        let canvas = try canvas()
        canvas.textLeading(50)

        let single = canvas.textBounds("AA", 0, 0)
        let triple = canvas.textBounds("AA\nAA\nAA", 0, 0)

        #expect(triple.height == single.height + 100)
        #expect(triple.width == single.width, "複数行の幅は最長行の幅（textWidth() と同じ規則）")
    }

    @Test("複数行の幅は最長行の幅")
    func multilineWidthIsTheLongestLine() throws {
        let canvas = try canvas()

        let bounds = canvas.textBounds("i\nMMMM\nii", 0, 0)

        #expect(bounds.width == canvas.textWidth("MMMM"))
    }

    // MARK: - textAlign() との整合

    @Test("既定（.left / .baseline）では x はそのまま、上端は ascent だけ上")
    func baselineAlignmentPlacesTheBox() throws {
        let canvas = try canvas()

        let bounds = canvas.textBounds("metaphor", 30, 40)

        #expect(bounds.x == 30)
        #expect(bounds.y == 40 - canvas.textAscent())
    }

    @Test(".center / .center では箱が基準点を中心に置かれる")
    func centerAlignmentCentersTheBox() throws {
        let canvas = try canvas()
        canvas.textAlign(.center, .center)

        let bounds = canvas.textBounds("metaphor", 30, 40)

        #expect(abs(bounds.x + bounds.width / 2 - 30) < 0.001)
        #expect(abs(bounds.y + bounds.height / 2 - 40) < 0.001)
    }

    @Test(".right / .bottom では基準点が箱の右下になる")
    func rightBottomAlignmentPlacesTheBox() throws {
        let canvas = try canvas()
        canvas.textAlign(.right, .bottom)

        let bounds = canvas.textBounds("metaphor", 30, 40)

        #expect(abs(bounds.x + bounds.width - 30) < 0.001)
        #expect(abs(bounds.y + bounds.height - 40) < 0.001)
    }

    @Test(".top では上端がそのまま y に来る")
    func topAlignmentPlacesTheBox() throws {
        let canvas = try canvas()
        canvas.textAlign(.left, .top)

        #expect(canvas.textBounds("metaphor", 30, 40).y == 40)
    }

    // MARK: - フォント状態への追随

    @Test("textSize() を変えると箱も変わる")
    func boundsFollowTextSize() throws {
        let canvas = try canvas(size: 16)
        let small = canvas.textBounds("metaphor", 0, 0)
        canvas.textSize(64)
        let large = canvas.textBounds("metaphor", 0, 0)

        #expect(large.width > small.width * 3)
        #expect(large.height > small.height * 3)
    }

    // MARK: - 境界値

    @Test("空文字列は大きさ 0 の箱（text() が何も描かないのと揃える）")
    func emptyStringHasNoBox() throws {
        let canvas = try canvas()
        canvas.textAlign(.center, .center)

        #expect(canvas.textBounds("", 30, 40) == TextBounds(x: 30, y: 40, width: 0, height: 0))
    }

    @Test("1 文字でも幅は textWidth() と一致する")
    func singleCharacterWidth() throws {
        let canvas = try canvas()

        #expect(canvas.textBounds("i", 0, 0).width == canvas.textWidth("i"))
    }

    // MARK: - 描いた絵との突き合わせ

    /// 数値どうしの恒等式だけでは「両方いっしょに間違える」を捕まえられないので、
    /// 実際に描いたインクが箱の中に収まっているかを見る。
    ///
    /// advance ベースなので墨は端から僅かに出うる（doc の callout どおり）。等幅で
    /// はみ出しの小さい `SpaceMono-Regular` を使い、余裕を 2px 取る。
    @Test("描いたインクは箱の中に収まる")
    func inkFallsInsideTheBox() throws {
        let font = try TextStyleResolutionTests.registerSingleFaceFixture()
        let width = 240
        let height = 120
        var helper = try RenderTestHelper(width: width, height: height)
        helper.setClearColor(r: 0, g: 0, b: 0)
        helper.canvas.textFont(font)
        helper.canvas.textSize(40)
        helper.canvas.textAlign(.left, .top)

        let bounds = helper.canvas.textBounds("Mango", 20, 20)
        try helper.render { canvas in
            canvas.fill(255)
            canvas.text("Mango", 20, 20)
        }

        let threshold: Float = 0.004
        let columns = (0..<width).map {
            helper.averageColor(inRect: $0, y: 0, width: 1, height: height).r
        }
        let rows = (0..<height).map {
            helper.averageColor(inRect: 0, y: $0, width: width, height: 1).r
        }
        let inkedColumns = columns.indices.filter { columns[$0] > threshold }
        let inkedRows = rows.indices.filter { rows[$0] > threshold }
        let left = try #require(inkedColumns.first, "文字が描かれていない")
        let right = try #require(inkedColumns.last)
        let top = try #require(inkedRows.first)
        let bottom = try #require(inkedRows.last)

        let slack: Float = 2
        #expect(
            Float(left) >= bounds.x - slack,
            "インクが箱の左に出ている（インク \(left) / 箱 \(bounds.x)）")
        #expect(
            Float(right) <= bounds.x + bounds.width + slack,
            "インクが箱の右に出ている（インク \(right) / 箱の右端 \(bounds.x + bounds.width)）")
        #expect(
            Float(top) >= bounds.y - slack,
            "インクが箱の上に出ている（インク \(top) / 箱 \(bounds.y)）")
        #expect(
            Float(bottom) <= bounds.y + bounds.height + slack,
            "インクが箱の下に出ている（インク \(bottom) / 箱の下端 \(bounds.y + bounds.height)）")

        // 箱が無意味に大きくないことも見る（0 幅の箱なら上の 4 つは自明に通る）。
        #expect(
            Float(right - left + 1) > bounds.width * 0.7,
            "箱が実際の文字より大きすぎる（インク幅 \(right - left + 1)px / 箱 \(bounds.width)px）")
    }
}
