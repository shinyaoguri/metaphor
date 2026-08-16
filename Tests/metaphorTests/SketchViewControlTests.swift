import Testing
import Metal
import MetalKit
@testable import MetaphorCore
import MetaphorTestSupport

// このファイルは `SketchView`（SwiftUI 埋め込み経路）のアニメーション制御の配線を固定する（#808）。
//
// `SketchContext` の loop() / noLoop() / redraw() / frameRate() は、コールバックが nil なら
// 状態を変えるだけの no-op になる。SketchView.Coordinator はかつてレンダーコールバック
// （onDraw / onAfterDraw）しか繋いでおらず、この経路のスケッチでは noLoop() を呼んでも
// フレームが止まらなかった（isLooping だけ false になり実挙動と食い違う）。
// SketchRunner 側の同じ配線は SketchAPISurfaceTests が見ているので、ここは SketchView 側だけを見る。

/// ``SketchView/Coordinator`` を単体構築し、制御 API の効きを観測するためのハーネス。
///
/// `SketchView` 自体は `NSViewRepresentable` で SwiftUI のライフサイクルに乗るためテストから
/// 描けないが、配線を持つのは `Coordinator.initialize(view:)` なので、そこだけを直接呼ぶ
/// （`SketchAPISurfaceTests` が `SketchRunner` を単体構築するのと同じ形）。
@MainActor
private final class SketchViewHarness {
    let view = MetaphorMTKView()
    private var coordinator: SketchView.Coordinator!

    /// draw クロージャの呼び出し回数と、そのフレームで渡った `deltaTime`。
    private(set) var drawCalls = 0
    private(set) var deltaTimes: [Float] = []

    init(config: SketchConfig = SketchConfig(width: 64, height: 64)) throws {
        coordinator = SketchView.Coordinator(config: config, setup: nil) { [weak self] ctx in
            self?.drawCalls += 1
            self?.deltaTimes.append(ctx.deltaTime)
        }
        try coordinator.initialize(view: view)
    }

    var context: SketchContext {
        get throws { try #require(coordinator.sketchContext) }
    }

    var renderer: MetaphorRenderer {
        get throws { try #require(coordinator.renderer) }
    }
}

@Suite("SketchView animation control", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchViewControlTests {

    // 回帰テスト(#808): 未配線だと isLooping だけが false になり、MTKView は回り続けていた。
    @Test("noLoop() は MTKView を一時停止し、loop() で再開する")
    func noLoopPausesViewAndLoopResumes() throws {
        let harness = try SketchViewHarness()
        let context = try harness.context

        #expect(harness.view.isPaused == false, "初期状態はループ中")

        context.noLoop()
        #expect(context.isLooping == false)
        #expect(harness.view.isPaused == true,
                "未配線だと isLooping だけ false になり、フレームは回り続ける(#808)")

        context.loop()
        #expect(context.isLooping == true)
        #expect(harness.view.isPaused == false)
    }

    // 回帰テスト(#808): redraw() はコールバック未配線では完全に無反応だった。
    @Test("redraw() は停止中でも draw クロージャをちょうど 1 回走らせる")
    func redrawRunsExactlyOneFrame() throws {
        let harness = try SketchViewHarness()
        let context = try harness.context

        context.noLoop()
        let before = harness.drawCalls

        context.redraw()

        #expect(harness.drawCalls == before + 1,
                "実測 \(harness.drawCalls - before) フレーム: 0 なら未配線、2 以上なら二重描画")
    }

    // 境界値(#358 と同じクランプ): 0 以下は 1 へ丸め、両方の宛先へ同じ値を渡す。
    // SketchRunner.handleFrameRate と共通の clampedFrameRate(_:) を通ることも兼ねて見る。
    @Test("frameRate() は 0 以下をクランプし targetFPS と preferredFramesPerSecond の両方へ渡す")
    func frameRateClampsAllPaths() throws {
        let harness = try SketchViewHarness()
        let context = try harness.context
        let renderer = try harness.renderer

        context.frameRate(0)
        #expect(renderer.targetFPS == 1, "targetFPS は 1 にクランプされるべき")
        #expect(harness.view.preferredFramesPerSecond == 1,
                "MTKView.preferredFramesPerSecond も 1 にクランプされるべき")

        context.frameRate(-5)
        #expect(renderer.targetFPS == 1)
        #expect(harness.view.preferredFramesPerSecond == 1)

        // 通常の正値は素通し。
        context.frameRate(30)
        #expect(renderer.targetFPS == 30)
        #expect(harness.view.preferredFramesPerSecond == 30)
    }

    // 回帰テスト(#793 と同じ跳ね): 時計（renderer.elapsedTime）は止めている間も進むので、
    // ループ再開の前に起点を寄せ直さないと、再開後の最初のフレームの deltaTime に
    // 「止めていた実時間まるごと」が乗る（それを積分に使う側が 1 回で吹き飛ぶ）。
    @Test("loop() で再開した直後の deltaTime に止めていた実時間が乗らない")
    func loopResyncsFrameClock() throws {
        let harness = try SketchViewHarness()
        let context = try harness.context
        let renderer = try harness.renderer

        // 1 フレーム描いた直後に noLoop() したとみなす。
        renderer.renderFrame()
        context.noLoop()

        // 止めている間に時計が 5 秒進んだ状況を作る（clockOffset は elapsedTime に乗る）。
        renderer.clockOffset = 5.0
        context.loop()

        renderer.renderFrame()

        let resumedDelta = try #require(harness.deltaTimes.last)
        #expect(resumedDelta < 0.1, "実測 \(resumedDelta)s: 止めていた 5 秒が乗っている")
    }
}
