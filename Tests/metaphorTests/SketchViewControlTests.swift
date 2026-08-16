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

    init(
        config: SketchConfig = SketchConfig(width: 64, height: 64),
        setup: (@MainActor (SketchContext) -> Void)? = nil
    ) throws {
        coordinator = SketchView.Coordinator(config: config, setup: setup) { [weak self] ctx in
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

// このスイートは `SketchView` 経路の `createCanvas()` の配線を固定する（#828）。
//
// `SketchContext.createCanvas` も onCreateCanvas が nil なら完全な no-op で、
// SketchView.Coordinator にはこの配線が無かった（#827 が入れた制御 4 本の隣に残っていた）。
// SketchRunner 側は SketchAPISurfaceTests が見ているので、ここは SketchView 側だけを見る。
@Suite("SketchView createCanvas", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchViewCreateCanvasTests {

    // 回帰テスト(#828): 未配線だと setup で createCanvas() を呼んでも寸法が動かない。
    @Test("setup 内の createCanvas() が ctx の寸法とオフスクリーンテクスチャの両方を作り替える")
    func createCanvasResizesContextAndTextures() throws {
        let harness = try SketchViewHarness(config: SketchConfig(width: 64, height: 64)) { ctx in
            ctx.createCanvas(width: 128, height: 32)
        }
        let context = try harness.context
        let renderer = try harness.renderer

        #expect(context.width == 128, "実測 \(context.width): 64 のままなら未配線(#828)")
        #expect(context.height == 32, "実測 \(context.height): 64 のままなら未配線(#828)")

        // ctx の数値だけ書き換えて終わっていないこと。ブリットのレターボックスは
        // textureManager.aspectRatio を見るので、ここが動かないと画面は元の比率のまま。
        #expect(renderer.textureManager.width == 128)
        #expect(renderer.textureManager.height == 32)
        #expect(renderer.textureManager.aspectRatio == 4.0)
    }

    // 回帰テスト(#828): setup をフレームの中で呼んでいると、resizeCanvas が
    // inflightSemaphore を 3 つ取りに行くのに renderFrame() が 1 つ掴んだままなので、
    // 5 秒待って "Timed out waiting for in-flight frame during resize" に落ちる。
    // 実時間で見るしかない性質のずれなので、タイムアウト（5s）の半分を閾値にする。
    // 初期化だけでなく最初のフレームまで含めて測る: setup をフレームの中で呼ぶ旧形では
    // createCanvas() が走るのが最初の renderFrame() の中なので、そこまで回さないと現れない。
    @Test("setup 内の createCanvas() がインフライトフレームのタイムアウトで止まらない")
    func createCanvasDoesNotStallOnInflightFrames() throws {
        let started = ContinuousClock.now
        let harness = try SketchViewHarness(config: SketchConfig(width: 64, height: 64)) { ctx in
            ctx.createCanvas(width: 128, height: 32)
        }
        try harness.renderer.renderFrame()
        let elapsed = ContinuousClock.now - started

        #expect(elapsed < .seconds(2.5),
                "実測 \(elapsed): 5 秒級なら setup がフレームの中で走っている(#828)")
    }

    // 回帰テスト(#828): setup をフレームの外へ移した副作用の押さえ。
    // setup 内の noLoop() をその場で効かせると 1 フレームも描かれないまま止まる
    // （p5.js は setup 後に draw を 1 回描いてから止まる）。
    @Test("setup 内の noLoop() でも初回フレームは描かれ、その後だけ止まる")
    func noLoopInSetupStillDrawsFirstFrame() throws {
        let harness = try SketchViewHarness(config: SketchConfig(width: 64, height: 64)) { ctx in
            ctx.noLoop()
        }
        let context = try harness.context
        let renderer = try harness.renderer

        #expect(context.isLooping == false)
        #expect(harness.view.isPaused == false, "初回フレームの前に止めてはいけない(#828)")
        #expect(harness.drawCalls == 0)

        renderer.renderFrame()

        #expect(harness.drawCalls == 1, "実測 \(harness.drawCalls) フレーム: 0 なら真っ黒のまま")
        #expect(harness.view.isPaused == true, "初回フレームを描いたら止まるべき")

        // 2 フレーム目が勝手に走らないこと（止め忘れの検出）。
        renderer.renderFrame()
        #expect(harness.drawCalls == 2,
                "renderFrame() を直接叩けば描かれる。止めているのは MTKView 側の駆動だけ")
    }

    // setup で noLoop() を呼ばない通常のスケッチが、初回フレームの後で止まらないこと。
    @Test("setup で noLoop() を呼ばなければ初回フレームの後も動き続ける")
    func loopingSketchKeepsRunningAfterFirstFrame() throws {
        let harness = try SketchViewHarness(config: SketchConfig(width: 64, height: 64)) { ctx in
            ctx.createCanvas(width: 32, height: 32)
        }
        let renderer = try harness.renderer

        renderer.renderFrame()

        #expect(harness.view.isPaused == false, "止める理由が無いのに止まっている")
    }
}
