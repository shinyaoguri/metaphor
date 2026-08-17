import Testing
import Metal
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - テキストの色

/// `text()` が **fill 色**で塗られることを画素で確かめる（#516 の回帰テスト）。
///
/// グリフはアンチエイリアスがかかるため 1 画素を狙い撃ちしても不安定なので、
/// 黒背景のキャンバス全体を平均して「どのチャンネルが強いか」で色相を見る。
@Suite("Text rendering color", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TextRenderingColorTests {

    private static let canvasWidth = 160
    private static let canvasHeight = 64

    /// 黒背景に文字だけを描き、キャンバス全体の平均色を返す。
    private func renderText(
        _ draw: (Canvas2D) -> Void
    ) throws -> (r: Float, g: Float, b: Float, a: Float) {
        var helper = try RenderTestHelper(width: Self.canvasWidth, height: Self.canvasHeight)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.textSize(40)
            draw(canvas)
        }
        return helper.averageColor(
            inRect: 0, y: 0, width: Self.canvasWidth, height: Self.canvasHeight
        )
    }

    @Test("text() は fill 色で塗られる")
    func textUsesFillColor() throws {
        let warm = try renderText { canvas in
            canvas.fill(230, 90, 70)
            canvas.text("MW", 10, 50)
        }
        #expect(warm.r > 0.01, "文字が描かれていない（平均 R=\(warm.r)）")
        #expect(warm.r > warm.g * 1.5 && warm.g > warm.b,
                "fill(230, 90, 70) の色相になっていない: R=\(warm.r) G=\(warm.g) B=\(warm.b)")

        let cool = try renderText { canvas in
            canvas.fill(70, 90, 230)
            canvas.text("MW", 10, 50)
        }
        #expect(cool.b > cool.r * 1.5 && cool.g > cool.r,
                "fill(70, 90, 230) の色相になっていない: R=\(cool.r) G=\(cool.g) B=\(cool.b)")
    }

    @Test("text() の色は fill を変えると変わる")
    func textColorFollowsFill() throws {
        let sameFill = try renderText { canvas in
            canvas.fill(255, 0, 0)
            canvas.text("M", 10, 50)
            canvas.text("M", 90, 50)
        }
        let differentFill = try renderText { canvas in
            canvas.fill(255, 0, 0)
            canvas.text("M", 10, 50)
            canvas.fill(0, 0, 255)
            canvas.text("M", 90, 50)
        }
        // 同じ位置・同じ字形なので、fill を変えた分だけ B が増え R が減る
        #expect(differentFill.b > sameFill.b + 0.005,
                "2 文字目の fill が反映されていない: B \(sameFill.b) → \(differentFill.b)")
        #expect(differentFill.r < sameFill.r,
                "2 文字目が赤のまま描かれている: R \(sameFill.r) → \(differentFill.r)")
    }

    @Test("tint() は文字色を変えない（画像専用）")
    func tintDoesNotColorText() throws {
        let tinted = try renderText { canvas in
            canvas.fill(255)
            canvas.tint(255, 0, 0)
            canvas.text("MW", 10, 50)
        }
        #expect(tinted.r > 0.01, "文字が描かれていない（平均 R=\(tinted.r)）")
        // 白い fill なので、tint を無視していれば 3 チャンネルがほぼ揃う
        #expect(tinted.g > tinted.r * 0.9 && tinted.b > tinted.r * 0.9,
                "tint が文字色に漏れている: R=\(tinted.r) G=\(tinted.g) B=\(tinted.b)")
    }

    @Test("矩形を取る text() も fill 色で塗られる")
    func wrappedTextUsesFillColor() throws {
        let warm = try renderText { canvas in
            canvas.textSize(24)
            canvas.fill(230, 90, 70)
            canvas.text("MW MW", 10, 6, 140, 52)
        }
        #expect(warm.r > 0.01, "文字が描かれていない（平均 R=\(warm.r)）")
        #expect(warm.r > warm.g * 1.5 && warm.g > warm.b,
                "fill(230, 90, 70) の色相になっていない: R=\(warm.r) G=\(warm.g) B=\(warm.b)")
    }

    /// `noFill()` は `text()` に効かない（#519 で意図的にそう決めた）。
    ///
    /// Processing はグリフを塗り図形として扱うので `noFill()` で文字が消えるが、
    /// metaphor のテキストに stroke 経路は無く、「消える」を選ぶと移植したスケッチが
    /// 黙って文字を失う。移行ガイドの Pitfalls に書いた約束をここで固定する。
    @Test("noFill() は text() を消さない（直前の fill 色で描かれる）")
    func noFillDoesNotHideText() throws {
        let filled = try renderText { canvas in
            canvas.fill(230, 90, 70)
            canvas.text("MW", 10, 50)
        }
        let afterNoFill = try renderText { canvas in
            canvas.fill(230, 90, 70)
            canvas.noFill()
            canvas.text("MW", 10, 50)
        }
        #expect(afterNoFill.r > 0.01,
                "noFill() の後で文字が消えている（平均 R=\(afterNoFill.r)）")
        // 「描かれる」だけでなく「直前の fill 色のまま」であることまで見る
        #expect(abs(afterNoFill.r - filled.r) < 0.005
                && abs(afterNoFill.g - filled.g) < 0.005
                && abs(afterNoFill.b - filled.b) < 0.005,
                """
                noFill() が文字色を変えている: \
                fill 時 R=\(filled.r) G=\(filled.g) B=\(filled.b) / \
                noFill 後 R=\(afterNoFill.r) G=\(afterNoFill.g) B=\(afterNoFill.b)
                """)
    }

    /// 文字を消したいときの案内（移行ガイドに書いた代替手段）が実際に効くこと。
    /// `noFill()` と違い、fill のアルファはグリフまで届く。
    @Test("fill のアルファ 0 なら text() は見えなくなる")
    func zeroAlphaFillHidesText() throws {
        let transparent = try renderText { canvas in
            canvas.fill(230, 90, 70, 0)
            canvas.text("MW", 10, 50)
        }
        #expect(transparent.r < 0.001 && transparent.g < 0.001 && transparent.b < 0.001,
                """
                アルファ 0 の fill でも文字が見えている: \
                R=\(transparent.r) G=\(transparent.g) B=\(transparent.b)
                """)
    }
}

// MARK: - テキストの向き

/// 矩形を取る `text(_:_:_:_:_:)` が**上下・左右とも正しい向き**で描かれることを
/// 画素で確かめる（#504 の回帰テスト）。
///
/// 向きは目で見ないと分からない類なので、キャンバスを行ごと・列ごとの「インク量」
/// に落として非対称な文字列で見る。行の順序（複数行）、1 行の中でのグリフの向き、
/// 進行方向の 3 つを別々に固定し、3 引数版（グリフアトラス経路。もともと正しい）
/// と同じ結論になることも押さえる。
@Suite("Text orientation", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TextOrientationTests {

    private static let canvasWidth = 240
    private static let canvasHeight = 160

    /// インクとみなす明るさ。背景は黒なので、アンチエイリアスの裾を拾う程度に低く取る。
    private static let inkThreshold: Float = 0.004

    private func render(_ draw: (Canvas2D) -> Void) throws -> RenderTestHelper {
        var helper = try RenderTestHelper(width: Self.canvasWidth, height: Self.canvasHeight)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(255)
            draw(canvas)
        }
        return helper
    }

    /// 行ごとのインク量（上から順）。
    private func rowInk(_ helper: RenderTestHelper) -> [Float] {
        (0..<Self.canvasHeight).map {
            helper.averageColor(inRect: 0, y: $0, width: Self.canvasWidth, height: 1).r
        }
    }

    /// 列ごとのインク量（左から順）。
    private func columnInk(_ helper: RenderTestHelper) -> [Float] {
        (0..<Self.canvasWidth).map {
            helper.averageColor(inRect: $0, y: 0, width: 1, height: Self.canvasHeight).r
        }
    }

    /// インクのある範囲を半分に割り、前半・後半の総量を返す。
    ///
    /// 文字の実寸（行高・字幅）を知らずに済ませるため、描かれた範囲そのものを
    /// 基準にする。インクが無ければ (0, 0) を返し、呼び出し側の総量チェックで落ちる。
    private func balance(_ profile: [Float]) -> (leading: Float, trailing: Float) {
        let inked = profile.indices.filter { profile[$0] > Self.inkThreshold }
        guard let first = inked.first, let last = inked.last, last > first else { return (0, 0) }
        let mid = (first + last) / 2
        return (profile[first...mid].reduce(0, +), profile[(mid + 1)...last].reduce(0, +))
    }

    @Test("矩形を取る text() は 1 行目を上に描く")
    func wrappedTextKeepsLineOrder() throws {
        // 1 行目はインクが多く、2 行目はほとんど無い。上下が反転すれば逆になる。
        let helper = try render { canvas in
            canvas.textSize(24)
            canvas.textAlign(.left, .top)
            canvas.text("MMMM\n.", 20, 20, 200, 120)
        }
        let (top, bottom) = balance(rowInk(helper))
        #expect(top + bottom > 0.01, "文字が描かれていない（総インク \(top + bottom)）")
        #expect(top > bottom * 3,
                "1 行目が下に来ている（上半分 \(top) / 下半分 \(bottom)）")
    }

    @Test("矩形を取る text() のグリフが上下反転しない")
    func wrappedTextKeepsGlyphOrientation() throws {
        // "T" は上部に横棒があり、"." はベースラインだけ。上半分のインクが多い。
        let helper = try render { canvas in
            canvas.textSize(48)
            canvas.textAlign(.left, .top)
            canvas.text("T.", 20, 20, 200, 120)
        }
        let (top, bottom) = balance(rowInk(helper))
        #expect(top + bottom > 0.01, "文字が描かれていない（総インク \(top + bottom)）")
        #expect(top > bottom * 1.5,
                "グリフが上下反転している（上半分 \(top) / 下半分 \(bottom)）")
    }

    @Test("矩形を取る text() のグリフが左右反転しない")
    func wrappedTextKeepsGlyphDirection() throws {
        // "M..." はインクが左端の 1 文字に偏る。左右が反転すれば "...M" になる。
        // 幅の広い "M" 1 文字ぶんで折り返さないよう、点は 3 つ並べて重心をずらす。
        let helper = try render { canvas in
            canvas.textSize(48)
            canvas.textAlign(.left, .top)
            canvas.text("M...", 20, 20, 200, 120)
        }
        let (left, right) = balance(columnInk(helper))
        #expect(left + right > 0.01, "文字が描かれていない（総インク \(left + right)）")
        #expect(left > right * 3,
                "グリフが左右反転している（左半分 \(left) / 右半分 \(right)）")
    }

    @Test("3 引数の text() と同じ向きで描かれる")
    func wrappedTextMatchesThreeArgumentText() throws {
        // グリフアトラス経路（もともと正しい）を基準に、同じ結論になることを押さえる。
        let plain = try render { canvas in
            canvas.textSize(48)
            canvas.text("T.", 20, 100)
        }
        let wrapped = try render { canvas in
            canvas.textSize(48)
            canvas.textAlign(.left, .top)
            canvas.text("T.", 20, 20, 200, 120)
        }
        let plainRows = balance(rowInk(plain))
        let wrappedRows = balance(rowInk(wrapped))
        #expect(plainRows.leading > plainRows.trailing,
                "基準側が壊れている（上半分 \(plainRows.leading) / 下半分 \(plainRows.trailing)）")
        #expect(wrappedRows.leading > wrappedRows.trailing,
                "矩形版だけ向きが違う（上半分 \(wrappedRows.leading) / 下半分 \(wrappedRows.trailing)）")
    }
}

// MARK: - 複数行テキスト

/// 複数行テキストが描けることを画素で確かめる（#744 の回帰テスト）。
///
/// 3 引数版の `\n` 分割、矩形版の折り返し、`textLeading()` の単位（ピクセル）を
/// 別々に固定する。行の位置は目で見ないと分からない類なので、キャンバスを行ごとの
/// 「インク量」に落とし、インクの帯（連続して閾値を超える行の並び）の数と間隔で見る。
@Suite("Multiline text", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct MultilineTextTests {

    private static let canvasWidth = 260
    private static let canvasHeight = 220

    /// インクとみなす明るさ。背景は黒なので、アンチエイリアスの裾を拾う程度に低く取る。
    private static let inkThreshold: Float = 0.004

    private func render(_ draw: (Canvas2D) -> Void) throws -> RenderTestHelper {
        var helper = try RenderTestHelper(width: Self.canvasWidth, height: Self.canvasHeight)
        helper.setClearColor(r: 0, g: 0, b: 0)
        try helper.render { canvas in
            canvas.fill(255)
            draw(canvas)
        }
        return helper
    }

    /// 行ごとのインク量（上から順）。
    private func rowInk(_ helper: RenderTestHelper) -> [Float] {
        (0..<Self.canvasHeight).map {
            helper.averageColor(inRect: 0, y: $0, width: Self.canvasWidth, height: 1).r
        }
    }

    /// 列ごとのインク量（左から順）。
    private func columnInk(_ helper: RenderTestHelper) -> [Float] {
        (0..<Self.canvasWidth).map {
            helper.averageColor(inRect: $0, y: 0, width: 1, height: Self.canvasHeight).r
        }
    }

    /// インクのある範囲（最初と最後の位置）。インクが無ければ nil。
    private func inkExtent(_ profile: [Float]) -> (first: Int, last: Int)? {
        let inked = profile.indices.filter { profile[$0] > Self.inkThreshold }
        guard let first = inked.first, let last = inked.last else { return nil }
        return (first, last)
    }

    /// 連続して閾値を超える区間（インクの帯）を上から順に返す。
    ///
    /// 行同士が離れていれば帯が分かれるので、帯の数がそのまま「描かれた行数」になる。
    private func inkBands(_ profile: [Float]) -> [(first: Int, last: Int, ink: Float)] {
        var bands: [(first: Int, last: Int, ink: Float)] = []
        var start: Int?
        var sum: Float = 0
        for i in profile.indices {
            if profile[i] > Self.inkThreshold {
                if start == nil { start = i; sum = 0 }
                sum += profile[i]
            } else if let s = start {
                bands.append((s, i - 1, sum))
                start = nil
            }
        }
        if let s = start { bands.append((s, profile.count - 1, sum)) }
        return bands
    }

    @Test("3 引数の text() は \\n で行を分ける")
    func plainTextSplitsOnNewline() throws {
        let helper = try render { canvas in
            canvas.textSize(20)
            canvas.textAlign(.left, .top)
            canvas.text("MMM\nM", 20, 20)
        }
        let bands = inkBands(rowInk(helper))
        #expect(bands.count == 2,
                "2 行に分かれていない（インクの帯 \(bands.count) 本: \(bands.map { "\($0.first)...\($0.last)" })）")
        if bands.count == 2 {
            #expect(bands[0].ink > bands[1].ink,
                    "1 行目が下に来ている（上の帯 \(bands[0].ink) / 下の帯 \(bands[1].ink)）")
        }
    }

    @Test("3 引数の text() は \\n で幅を連結しない")
    func plainTextNewlineDoesNotConcatenate() throws {
        var widths: (split: Float, joined: Float) = (0, 0)
        let helper = try render { canvas in
            canvas.textSize(20)
            canvas.textAlign(.left, .top)
            canvas.text("AA\nBB", 20, 20)
            widths.joined = canvas.textWidth("AABB")
            widths.split = canvas.textWidth("AA")
        }
        guard let extent = inkExtent(columnInk(helper)) else {
            Issue.record("文字が描かれていない")
            return
        }
        let drawn = Float(extent.last - extent.first + 1)
        #expect(drawn < widths.joined * 0.75,
                "\\n が捨てられて 1 行に連結された（描画幅 \(drawn) / textWidth(\"AABB\") \(widths.joined)）")
        #expect(widths.split == canvas2DTextWidth(helper, "AA\nBB"),
                "textWidth() が改行を含む文字列で最長行の幅を返していない")
    }

    /// `textWidth()` を描画後のキャンバスから引く（`render` の外でも同じ状態で測るため）。
    private func canvas2DTextWidth(_ helper: RenderTestHelper, _ string: String) -> Float {
        helper.canvas.textWidth(string)
    }

    @Test("矩形を取る text() はピクセル単位の leading で折り返す")
    func wrappedTextWrapsWithPixelLeading() throws {
        // 検査盤 0816-adversary の F6 と同じ条件（leading をピクセルのつもりで指定する）。
        let helper = try render { canvas in
            canvas.textSize(14)
            canvas.textAlign(.left, .top)
            canvas.textLeading(20)
            canvas.text("wrap this sentence into several lines", 10, 10, 120, 100)
        }
        guard let extent = inkExtent(rowInk(helper)) else {
            Issue.record("文字が描かれていない")
            return
        }
        let drawnHeight = extent.last - extent.first + 1
        #expect(drawnHeight > 26,
                "折り返していない（インクの高さ \(drawnHeight)px — 1 行ぶんしかない）")
    }

    @Test("textLeading() はピクセル単位で行間を決める")
    func textLeadingIsInPixels() throws {
        func lineDistance(leading: Float) throws -> Int {
            let helper = try render { canvas in
                canvas.textSize(20)
                canvas.textAlign(.left, .top)
                canvas.textLeading(leading)
                canvas.text("MM\nMM", 20, 20)
            }
            let bands = inkBands(rowInk(helper))
            guard bands.count == 2 else {
                Issue.record("leading \(leading) で 2 行にならなかった（帯 \(bands.count) 本）")
                return 0
            }
            return bands[1].first - bands[0].first
        }

        let narrow = try lineDistance(leading: 30)
        let wide = try lineDistance(leading: 60)
        #expect(narrow > 0 && wide > 0, "行間を測れなかった")
        // 30 → 60 で行の間隔もおよそ 2 倍になる（倍率として解釈していれば桁が違う）
        #expect(abs(narrow - 30) <= 2, "leading 30 が \(narrow)px になっている")
        #expect(abs(wide - 60) <= 2, "leading 60 が \(wide)px になっている")
    }

    @Test("textSize() は leading を自動へ戻す")
    func textSizeResetsLeading() throws {
        func lineDistance(_ draw: (Canvas2D) -> Void) throws -> Int {
            let helper = try render { canvas in
                canvas.textAlign(.left, .top)
                draw(canvas)
                canvas.text("MM\nMM", 20, 20)
            }
            let bands = inkBands(rowInk(helper))
            guard bands.count == 2 else {
                Issue.record("2 行にならなかった（帯 \(bands.count) 本）")
                return 0
            }
            return bands[1].first - bands[0].first
        }

        let auto = try lineDistance { $0.textSize(20) }
        let reset = try lineDistance { canvas in
            canvas.textSize(20)
            canvas.textLeading(60)
            canvas.textSize(20)
        }
        #expect(auto > 0, "既定の行間を測れなかった")
        #expect(abs(reset - auto) <= 2,
                "textSize() の後も textLeading(60) が残っている（\(reset)px / 既定 \(auto)px）")
    }
}
