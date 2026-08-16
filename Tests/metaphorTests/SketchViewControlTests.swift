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

/// `resizeCanvas` のインフライトフレームのドレイン待ちタイムアウト。
///
/// 壁時計の絶対値で閾値を切ると CI で揺れる（#891）ので、タイムアウトの値そのものを物差しにする。
private let resizeDrainTimeout = Duration.seconds(MetaphorRenderer.inflightDrainTimeoutSeconds)

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

    /// 毎フレーム draw クロージャの末尾で走る観測フック（#856 で追加）。
    ///
    /// init の引数にすると、既存の呼び出し側の末尾クロージャが `setup` ではなく
    /// こちらへ結び付いてしまう（後方マッチング）ため、構築後に差し込む形にしている。
    var onDraw: (@MainActor (SketchContext) -> Void)?

    init(
        config: SketchConfig = SketchConfig(width: 64, height: 64),
        setup: (@MainActor (SketchContext) -> Void)? = nil
    ) throws {
        coordinator = SketchView.Coordinator(config: config, setup: setup) { [weak self] ctx in
            self?.drawCalls += 1
            self?.deltaTimes.append(ctx.deltaTime)
            self?.onDraw?(ctx)
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
    // 実時間で見るしかない性質のずれなので、タイムアウトそのものの半分を閾値にする
    // （壁時計の絶対値で切ると CI で揺れる。#891）。
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

        #expect(elapsed < resizeDrainTimeout / 2,
                "実測 \(elapsed): タイムアウト(\(resizeDrainTimeout))級なら setup がフレームの中で走っている(#828)")
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

// このスイートは `draw()` の**中**から `createCanvas()` を呼んだときの振る舞いを固定する（#856）。
//
// `MetaphorRenderer.resizeCanvas` は古いテクスチャを GPU が掴んでいないことを保証するため
// `inflightSemaphore`（値 3）を 3 つとも取りに行くが、`renderFrame()` は先頭で 1 つ取って
// GPU 完了ハンドラまで保持する。`draw()` はそのフレームの中で走るので、フレーム中の
// `createCanvas()` は必ず 3 つ目で 5 秒待ってタイムアウトし、その後もそのまま
// `TextureManager` を差し替えて記録中のフレームを捨てていた。
// いまは待たずに弾き、そのフレームは元のキャンバスのまま描き切る。

/// `draw()` の中で観測した値の置き場（エスケープするクロージャから書き込むため参照型）。
@MainActor
private final class DrawProbe {
    var canvasBefore: Canvas2D?
    var canvasAfter: Canvas2D?
    var widthDuringDraw: Float = 0
    var isRenderingFrameDuringDraw = false
}

@Suite("SketchView createCanvas in draw", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchViewCreateCanvasInDrawTests {

    // 回帰テスト(#856): 修正前はここで 5 秒待たされていた。
    @Test("draw() 中の createCanvas() はインフライトフレームのドレイン待ちで止まらない")
    func createCanvasInDrawDoesNotStall() throws {
        let harness = try SketchViewHarness(config: SketchConfig(width: 64, height: 64))
        harness.onDraw = { ctx in
            ctx.createCanvas(width: 128, height: 32)
        }
        let renderer = try harness.renderer

        // 初期化コストを混ぜないよう、測るのはフレーム 1 枚ぶんだけにする。
        let started = ContinuousClock.now
        renderer.renderFrame()
        let elapsed = ContinuousClock.now - started

        #expect(elapsed < resizeDrainTimeout / 2,
                "実測 \(elapsed): タイムアウト(\(resizeDrainTimeout))級ならドレイン待ちに落ちている(#856)")
    }

    // 回帰テスト(#856): 弾くだけでなく「半端に効かせない」ことも見る。リサイズを飛ばしても
    // Canvas2D/Canvas3D を作り直してしまうと、その差し替えはエンコーダを持たない新品なので
    // 以降の描画がまるごと消え、スタイル状態も既定へ戻る。
    @Test("draw() 中の createCanvas() は無視され、そのフレームは元のキャンバスのまま続く")
    func createCanvasInDrawKeepsFrameIntact() throws {
        let probe = DrawProbe()
        let harness = try SketchViewHarness(config: SketchConfig(width: 64, height: 64))
        harness.onDraw = { ctx in
            probe.canvasBefore = ctx.canvas
            probe.isRenderingFrameDuringDraw = ctx.renderer.isRenderingFrame
            ctx.createCanvas(width: 128, height: 32)
            probe.canvasAfter = ctx.canvas
            probe.widthDuringDraw = ctx.width
        }
        let context = try harness.context
        let renderer = try harness.renderer

        renderer.renderFrame()

        #expect(probe.isRenderingFrameDuringDraw,
                "draw() の中なのに isRenderingFrame が立っていない(#856)")
        #expect(probe.canvasAfter === probe.canvasBefore,
                "フレームの途中で Canvas2D が差し替わると、以降の描画はエンコーダの無い新品へ落ちて消える(#856)")
        #expect(probe.widthDuringDraw == 64,
                "実測 \(probe.widthDuringDraw): 寸法だけ先に動くと draw() の残りが食い違う")
        #expect(context.width == 64)
        #expect(context.height == 64)
        #expect(renderer.textureManager.width == 64, "リサイズは行われないべき")
        #expect(renderer.textureManager.height == 64)
    }

    // 境界: 弾く印はフレームの外まで漏れない（漏れると createCanvas() が二度と効かなくなる）。
    @Test("フレームの外からの createCanvas() は draw() 中に弾かれた後も効く")
    func createCanvasOutsideFrameStillWorksAfterRejection() throws {
        let harness = try SketchViewHarness(config: SketchConfig(width: 64, height: 64))
        harness.onDraw = { ctx in
            ctx.createCanvas(width: 128, height: 32)
        }
        let context = try harness.context
        let renderer = try harness.renderer

        renderer.renderFrame()
        #expect(renderer.isRenderingFrame == false, "フレームを抜けたら印は下りているべき")

        // フレームの外（= 通常の setup() と同じ位置）なら従来どおり効く。
        harness.onDraw = nil
        context.createCanvas(width: 128, height: 32)

        #expect(context.width == 128, "実測 \(context.width): 印が漏れて弾かれ続けている(#856)")
        #expect(context.height == 32)
        #expect(renderer.textureManager.width == 128)
        #expect(renderer.textureManager.height == 32)
    }
}
