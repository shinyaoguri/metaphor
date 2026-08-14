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
