import AppKit
import Testing

@testable import MetaphorCore

// MARK: - ウィンドウの寿命は ARC だけが決める (Issue #835)

/// `NSWindow` の既定 `isReleasedWhenClosed = true` は「閉じたら AppKit が release を送る」
/// という MRR 時代の作法で、Swift の強参照でウィンドウを保持する metaphor
/// （``SketchWindow/window`` / ``SketchRunner/window``）と重なると二重解放になる。
/// 症状はセカンダリウィンドウを閉じて開き直したときの `SIGSEGV`（#835）。
///
/// クラッシュそのものが消えたかは GUI 実行でしか確かめられないため、ここでは
/// 「生成されたウィンドウに寿命の規約が入っていること」を固定する。
@Suite("スケッチウィンドウの寿命")
@MainActor
struct SketchWindowLifetimeTests {

    private func makeWindow(title: String = "lifetime-test") -> NSWindow {
        SketchWindowFactory.makeWindow(
            contentSize: NSSize(width: 320, height: 240),
            title: title,
            aspectRatio: NSSize(width: 640, height: 480)
        )
    }

    @Test("閉じても AppKit がウィンドウを解放しない")
    func windowIsNotReleasedWhenClosed() {
        #expect(makeWindow().isReleasedWhenClosed == false)
    }

    /// 修正前は解放済みオブジェクトを触る形になっていた経路
    /// （``SketchWindow/handleWindowClose()`` の後始末や
    /// `applicationShouldTerminateAfterLastWindowClosed` の `window?.isVisible`）。
    @Test("閉じた後も保持している参照から安全に読める")
    func windowStaysReadableAfterClose() {
        let window = makeWindow(title: "lifetime-close")
        window.close()

        #expect(window.isVisible == false)
        #expect(window.title == "lifetime-close")
    }

    /// 閉じる → 開き直す → もう一度閉じる（#835 の再現手順）。
    /// 既定のままだと 2 回目の close で release が二重に走る。
    @Test("閉じて開き直して再度閉じても参照が生き続ける")
    func windowSurvivesCloseReopenCloseCycle() {
        let window = makeWindow(title: "lifetime-cycle")

        window.close()
        window.orderFront(nil)
        window.close()

        #expect(window.isReleasedWhenClosed == false)
        #expect(window.title == "lifetime-cycle")
    }

    @Test("生成時点では画面に出さない（表示は呼び出し側の責務）")
    func doesNotPresentOnCreation() {
        #expect(makeWindow().isVisible == false)
    }

    @Test("サイズ・タイトル・アスペクト比が反映される")
    func appliesConfiguration() {
        let window = makeWindow(title: "lifetime-config")

        #expect(window.title == "lifetime-config")
        #expect(window.contentAspectRatio == NSSize(width: 640, height: 480))

        let content = window.contentRect(forFrameRect: window.frame)
        #expect(content.width == 320)
        #expect(content.height == 240)
    }
}
