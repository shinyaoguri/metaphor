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
