import Testing

@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - カスケードのスロットは閉じれば空く (Issue #837)

/// 以前は `SketchWindow` の静的カウンタが増えるだけで減らず、閉じて開き直すたびに
/// ウィンドウが 30pt ずつ右下へ流れ、繰り返すと画面外へ出ていた（#837 (a)）。
@Suite("カスケードスロットの割り当て")
struct CascadeSlotAllocationTests {

    @Test("1 枚も開いていなければ先頭のスロット")
    func firstSlotWhenEmpty() {
        #expect(SketchContext.nextCascadeIndex(inUse: []) == 0)
    }

    @Test("開いている枚数に応じて次のスロットへ進む")
    func advancesWhileSlotsAreTaken() {
        #expect(SketchContext.nextCascadeIndex(inUse: [0]) == 1)
        #expect(SketchContext.nextCascadeIndex(inUse: [0, 1]) == 2)
        #expect(SketchContext.nextCascadeIndex(inUse: [0, 1, 2]) == 3)
    }

    /// ここが #837 の肝。閉じたぶんスロットが空き、開き直しても流れ続けない。
    @Test("閉じて空いたスロットを埋め直す")
    func reusesFreedSlots() {
        #expect(SketchContext.nextCascadeIndex(inUse: [1, 2]) == 0)
        #expect(SketchContext.nextCascadeIndex(inUse: [0, 2]) == 1)
        #expect(SketchContext.nextCascadeIndex(inUse: [0, 1, 3]) == 2)
    }

    /// `secondaryWindows` の並びは閉じた順に崩れるので、順不同でも同じ答えになること。
    @Test("スロットの並び順に依存しない")
    func orderIndependent() {
        #expect(SketchContext.nextCascadeIndex(inUse: [2, 0]) == 1)
        #expect(SketchContext.nextCascadeIndex(inUse: [3, 1, 0]) == 2)
    }

    @Test("スロット 0 はオフセット無し、以降は 30pt ずつ")
    func offsetPerSlot() {
        #expect(SketchWindow.cascadeOffset(slot: 0) == 0)
        #expect(SketchWindow.cascadeOffset(slot: 1) == 30)
        #expect(SketchWindow.cascadeOffset(slot: 3) == 90)
    }
}

// MARK: - createWindow から見た振る舞い

/// ヘッドレス（`NSWindow` を作らない）で実際に開閉し、スロットの出入りを確かめる。
/// 非ヘッドレスは `makeKeyAndOrderFront` で画面にウィンドウが出るため構築しない
/// （`SketchWindowHeadlessTests` と同じ方針）。
@Suite("createWindow のカスケードスロット", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct CreateWindowCascadeTests {

    private func makeContext() throws -> SketchContext {
        let shared = try SharedMetalResources()
        let renderer = try MetaphorRenderer(sharedResources: shared, width: 32, height: 32)
        let context = SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
        context._sharedResources = shared
        return context
    }

    private func open(_ context: SketchContext, _ title: String) throws -> SketchWindow {
        try #require(
            context.createWindow(
                SketchWindowConfig(width: 32, height: 32, title: title),
                isHeadless: true
            )
        )
    }

    @Test("開いた順にスロットが振られる")
    func assignsSequentialSlots() throws {
        let context = try makeContext()
        defer { context.closeAllWindows() }

        let first = try open(context, "cascade-1")
        let second = try open(context, "cascade-2")
        let third = try open(context, "cascade-3")

        #expect(first.cascadeIndex == 0)
        #expect(second.cascadeIndex == 1)
        #expect(third.cascadeIndex == 2)
    }

    /// #837 の再現手順。修正前は開くたびにスロットが 0, 1, 2… と増え続けた。
    @Test("閉じて開き直してもスロットが流れない")
    func slotDoesNotDriftAcrossReopen() throws {
        let context = try makeContext()

        for _ in 0..<4 {
            let window = try open(context, "cascade-reopen")
            #expect(window.cascadeIndex == 0)
            window.close()
        }
    }

    @Test("真ん中を閉じると、その空きスロットが次に使われる")
    func fillsTheGapLeftInTheMiddle() throws {
        let context = try makeContext()
        defer { context.closeAllWindows() }

        _ = try open(context, "cascade-a")
        let middle = try open(context, "cascade-b")
        _ = try open(context, "cascade-c")

        middle.close()
        let replacement = try open(context, "cascade-d")

        #expect(replacement.cascadeIndex == 1)
    }

    @Test("closeAllWindows のあとは先頭のスロットへ戻る")
    func resetsAfterCloseAll() throws {
        let context = try makeContext()
        defer { context.closeAllWindows() }

        _ = try open(context, "cascade-x")
        _ = try open(context, "cascade-y")
        context.closeAllWindows()

        #expect(try open(context, "cascade-z").cascadeIndex == 0)
    }
}
