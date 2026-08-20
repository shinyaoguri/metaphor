import Testing

@testable import MetaphorCore
import MetaphorTestSupport

/// 描画クロージャが最初に見た値を持ち帰るための箱。
private final class FirstFrame: @unchecked Sendable {
    var seen = false
    var time: Float = -1
    var deltaTime: Float = -1

    @MainActor
    func record(_ ctx: SketchContext) {
        guard !seen else { return }
        seen = true
        time = ctx.time
        deltaTime = ctx.deltaTime
    }
}

// MARK: - セカンダリウィンドウの時計はスケッチ開始が起点 (Issue #836)

/// `SketchWindow` は 1 枚ごとに `MetaphorRenderer` を新規作成し、`startTime` はその窓の
/// **生成時刻**になる。修正前はプライマリと起点が食い違い、`context.time` の doc
/// （「スケッチ開始からの経過時間」）とも実装が食い違っていた（#836）。
///
/// 非ヘッドレスは `makeKeyAndOrderFront` で画面にウィンドウが出るため構築しない
/// （`SketchWindowHeadlessTests` と同じ方針）。
@Suite("セカンダリウィンドウの時計", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchWindowClockTests {

    private func makeWindow(clockOffset: Double, title: String) throws -> SketchWindow {
        try SketchWindow(
            config: SketchWindowConfig(width: 32, height: 32, title: title),
            sharedResources: try SharedMetalResources(),
            clockOffset: clockOffset,
            isHeadless: true
        )
    }

    @Test("渡した起点ぶん時計が進んだ状態で始まる")
    func startsFromTheGivenOffset() throws {
        let window = try makeWindow(clockOffset: 100, title: "clock-offset")
        defer { window.close() }

        #expect(window.context.renderer.elapsedTime >= 100)
    }

    @Test("起点を渡さなければ従来どおり 0 起点")
    func defaultsToZero() throws {
        let window = try makeWindow(clockOffset: 0, title: "clock-zero")
        defer { window.close() }

        #expect(window.context.renderer.elapsedTime < 1)
    }

    /// #836 の本体。修正前は最初のフレームの `time` がほぼ 0 だった。
    @Test("最初のフレームから time が起点を反映している")
    func firstFrameCarriesTheOffset() async throws {
        let window = try makeWindow(clockOffset: 100, title: "clock-first-frame")
        defer { window.close() }

        let first = FirstFrame()
        window.onDraw { first.record($0) }
        try await Task.sleep(nanoseconds: 300_000_000)

        try #require(first.seen)
        #expect(first.time >= 100)
    }

    /// 時計を進めた起点をそのまま置くと、最初の `deltaTime` が「経過時間まるごと」に化ける
    /// （`SketchRunner` が `preserveClock` で `FrameClock` を resync するのと同じ落とし穴。#793）。
    @Test("起点を進めても最初の deltaTime に起点が混ざらない")
    func firstDeltaTimeExcludesTheOffset() async throws {
        let offset: Double = 100
        let window = try makeWindow(clockOffset: offset, title: "clock-first-delta")
        defer { window.close() }

        let first = FirstFrame()
        window.onDraw { first.record($0) }
        try await Task.sleep(nanoseconds: 300_000_000)

        try #require(first.seen)
        // 正しい値は「ウィンドウ生成から最初のフレームまで」の実時間で、テストの並走負荷で
        // 伸びるため絶対値では固定できない。起点が混ざっていれば必ず offset 以上になるので、
        // そこを境にする。
        #expect(first.deltaTime >= 0)
        #expect(first.deltaTime < Float(offset))
    }
}

// MARK: - createWindow から見た振る舞い

@Suite("createWindow の時計合わせ", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct CreateWindowClockTests {

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

    /// 途中で開いたウィンドウがプライマリの時計を引き継ぐこと。修正前は
    /// 生成時刻が起点になるため、ここが 0 付近に落ちていた。
    @Test("途中で開いてもプライマリの経過時間から始まる")
    func inheritsPrimaryElapsedTime() async throws {
        let context = try makeContext()
        defer { context.closeAllWindows() }

        try await Task.sleep(nanoseconds: 250_000_000)
        let elapsed = context.renderer.elapsedTime
        try #require(elapsed >= 0.2, "プライマリの時計が進んでいる前提")

        let window = try #require(
            context.createWindow(
                SketchWindowConfig(width: 32, height: 32, title: "clock-inherit"),
                isHeadless: true
            )
        )

        // プライマリと同じ時刻から始まる（生成に掛かるぶんだけ進んでいてよい。上限は
        // 「0 起点へ落ちていない」ことが分かればよく、生成時間は負荷で伸びるので緩く取る）。
        #expect(window.context.renderer.elapsedTime >= elapsed)
        #expect(window.context.renderer.elapsedTime < elapsed + 60)
    }
}
