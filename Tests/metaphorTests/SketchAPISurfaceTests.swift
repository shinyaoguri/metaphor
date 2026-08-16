import Testing
import Metal
import Foundation
import os
import simd
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// このファイルは公開 API の中心である `Sources/MetaphorCore/Sketch/`
// （SketchConfig / SketchRunner / ライフサイクル / イベント配送 / 二層 API）の
// 挙動を固定する（Issue #331）。v0.9.0 で凍結する面の検出網であり、以降の
// rename・整理で挙動が変わったらここが赤くなることを狙う。

// MARK: - SketchRunner 配線のテストハーネス

/// ``SketchRunner`` の中核配線（`setupCore` / `configureRenderCallbacks` /
/// `connectInput`）をテストから再現する最小ハーネス。
///
/// `SketchRunner` 自体は `NSApplication` のランループ前提（`run` が `app.run()` で
/// ブロックし、`sketchRef` と `setup(sketch:)` は private）でテストから起動できない。
/// そこでランナーと**同じ順序・同じクロージャ**で部品を結線し、ランナーが依存して
/// いる不変条件（compute→draw の順序、フレーム状態の進み方、入力イベントの転送先）を
/// 検証する。ウィンドウ／タイマー操作だけは記録用のスタブに差し替える。
///
/// - Important: `SketchRunner.swift` の配線を変えたらこのハーネスも揃えること。
///   複製せずに本体を呼べるようにする案は Issue #357。
@MainActor
private final class SketchRunnerHarness {
    let renderer: MetaphorRenderer
    let context: SketchContext
    let sketch: any Sketch

    /// アニメーション制御コールバックの発火記録
    /// （実ランナーでは MTKView の isPaused / DispatchSourceTimer 操作にあたる）。
    private(set) var loopCalls = 0
    private(set) var noLoopCalls = 0
    private(set) var redrawCalls = 0
    private(set) var frameRateCalls: [Int] = []
    private(set) var createCanvasCalls: [(width: Int, height: Int)] = []

    /// onCompute と onDraw で共有する直前フレーム時刻（SketchRunner と同じ）。
    private let frameClock = FrameClock()

    init(
        sketch: any Sketch,
        config: SketchConfig = SketchConfig(width: 64, height: 64)
    ) throws {
        self.sketch = sketch

        // --- setupCore 相当 ---
        let renderer = try MetaphorRenderer(
            width: config.width, height: config.height, sampleCount: config.msaa
        )
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        context.isPrimary = true
        sketch._context = context

        self.renderer = renderer
        self.context = context

        // 制御コールバック（ランナーでは handleLoop / handleNoLoop / handleRedraw /
        // handleFrameRate / handleCreateCanvas）。
        context.onCreateCanvas = { [weak self] w, h in
            self?.createCanvasCalls.append((width: w, height: h))
        }
        context.onLoop = { [weak self] in self?.loopCalls += 1 }
        context.onNoLoop = { [weak self] in self?.noLoopCalls += 1 }
        context.onRedraw = { [weak self] in self?.redrawCalls += 1 }
        context.onFrameRate = { [weak self] fps in self?.frameRateCalls.append(fps) }

        // ヘッドレス相当（ディスプレイリンクから分離）。
        renderer.useExternalRenderLoop = true
    }

    /// `SketchRunner.setup` の後半（プラグイン登録 → setup() → 描画コールバック構成 →
    /// 開始通知）を再現します。
    func start(plugins: [PluginFactory] = []) {
        for factory in plugins {
            renderer.addPlugin(factory.create(), sketch: sketch)
        }

        // setup() 中に noLoop ハンドラを一時的に抑制（onDraw 構成前の早期一時停止防止）。
        context.onNoLoop = nil
        sketch.setup()
        context.onNoLoop = { [weak self] in self?.noLoopCalls += 1 }

        configureRenderCallbacks()
        renderer.notifyPluginsStart()
    }

    /// `SketchRunner.configureRenderCallbacks` と同一の結線。
    private func configureRenderCallbacks() {
        renderer.onCompute = { [weak self] commandBuffer, time in
            guard let self else { return }
            let t = Float(time)
            let dt = self.frameClock.delta(at: t)
            self.context.beginCompute(commandBuffer: commandBuffer, time: t, deltaTime: dt)
            self.sketch.compute()
            self.context.endCompute()
        }
        renderer.onDraw = { [weak self] encoder, time in
            guard let self else { return }
            let t = Float(time)
            let dt = self.frameClock.advance(to: t)
            self.context.beginFrame(
                encoder: encoder, time: t, deltaTime: dt, preciseTime: time
            )
            self.sketch.draw()
            self.context.endFrame()
        }
        renderer.onAfterDraw = { [weak self] commandBuffer in
            self?.context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
        }
    }

    /// `SketchRunner.connectInput` と同一の結線。
    func connectInput() {
        let input = renderer.input
        input.onMousePressed = { [weak self] x, y, button in
            self?.sketch.mousePressed()
            self?.renderer.notifyPluginsMouseEvent(x: x, y: y, button: button, type: .pressed)
        }
        input.onMouseReleased = { [weak self] x, y, button in
            self?.sketch.mouseReleased()
            self?.renderer.notifyPluginsMouseEvent(x: x, y: y, button: button, type: .released)
        }
        input.onMouseMoved = { [weak self] x, y in
            self?.sketch.mouseMoved()
            self?.renderer.notifyPluginsMouseEvent(x: x, y: y, button: nil, type: .moved)
        }
        input.onMouseDragged = { [weak self] x, y in
            self?.sketch.mouseDragged()
            self?.renderer.notifyPluginsMouseEvent(x: x, y: y, button: nil, type: .dragged)
        }
        input.onMouseScrolled = { [weak self] _, _ in
            guard let self else { return }
            self.sketch.mouseScrolled()
            let mx = self.renderer.input.mouseX
            let my = self.renderer.input.mouseY
            self.renderer.notifyPluginsMouseEvent(x: mx, y: my, button: nil, type: .scrolled)
        }
        input.onMouseClicked = { [weak self] x, y, button in
            self?.sketch.mouseClicked()
            self?.renderer.notifyPluginsMouseEvent(x: x, y: y, button: button, type: .clicked)
        }
        input.onKeyDown = { [weak self] keyCode, characters in
            guard let self else { return }
            self.sketch.keyPressed()
            // 実装本体（SketchRunner の static メソッド）をそのまま使う。
            if SketchRunner.producesCharacter(characters) {
                self.sketch.keyTyped()
            }
            self.renderer.notifyPluginsKeyEvent(
                key: characters?.first, keyCode: keyCode, type: .pressed
            )
        }
        input.onKeyUp = { [weak self] keyCode in
            self?.sketch.keyReleased()
            self?.renderer.notifyPluginsKeyEvent(key: nil, keyCode: keyCode, type: .released)
        }
        input.onFileDropInternal = { [weak self] paths in
            self?.sketch.fileDropped(paths)
        }
    }
}

// MARK: - 記録用スケッチ

/// ライフサイクル・イベントの呼び出しを順に記録する Sketch。
@MainActor
private final class RecordingSketch: Sketch {
    /// setup / compute / draw / 入力イベントの呼び出し順。
    var log: [String] = []
    /// compute / draw の各時点で観測した `frameCount`。
    var frameCountAtCompute: [Int] = []
    var frameCountAtDraw: [Int] = []
    /// compute / draw の各時点で観測した `(time, deltaTime)`。
    var clockAtCompute: [(time: Float, delta: Float)] = []
    var clockAtDraw: [(time: Float, delta: Float)] = []
    /// draw の各時点で観測した `(pmouseX, mouseX)`。
    var mouseAtDraw: [(pmouse: Float, mouse: Float)] = []
    /// `fileDropped` が受け取ったパス。
    var droppedPaths: [[String]] = []
    /// setup() 内で実行する追加処理（noLoop の検証など）。
    var setupBody: ((RecordingSketch) -> Void)?
    /// 独自 config（未設定なら protocol 既定）。
    var configOverride: SketchConfig?

    init() {}

    var config: SketchConfig { configOverride ?? SketchConfig() }

    func setup() {
        log.append("setup")
        setupBody?(self)
    }

    func compute() {
        log.append("compute")
        frameCountAtCompute.append(frameCount)
        clockAtCompute.append((time: time, delta: deltaTime))
    }

    func draw() {
        log.append("draw")
        frameCountAtDraw.append(frameCount)
        clockAtDraw.append((time: time, delta: deltaTime))
        mouseAtDraw.append((pmouse: pmouseX, mouse: mouseX))
    }

    func mousePressed() { log.append("mousePressed") }
    func mouseReleased() { log.append("mouseReleased") }
    func mouseMoved() { log.append("mouseMoved") }
    func mouseDragged() { log.append("mouseDragged") }
    func mouseScrolled() { log.append("mouseScrolled") }
    func mouseClicked() { log.append("mouseClicked") }
    func keyPressed() { log.append("keyPressed") }
    func keyReleased() { log.append("keyReleased") }
    func keyTyped() { log.append("keyTyped") }
    func fileDropped(_ paths: [String]) {
        log.append("fileDropped")
        droppedPaths.append(paths)
    }
}

/// `config` を一切上書きしない最小スケッチ（protocol 既定実装の確認用）。
@MainActor
private final class DefaultConfigSketch: Sketch {
    init() {}
}

// MARK: - 入力注入テスト用のヘルパ

/// 与えた行を順に返し、尽きたら nil を返す決定的なイベント供給元。
private final class EventLineFeeder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[String]>(initialState: [])

    init(_ lines: [String]) {
        lock.withLock { $0 = lines }
    }

    func next() -> String? {
        lock.withLock { lines in
            lines.isEmpty ? nil : lines.removeFirst()
        }
    }

    /// まだリーダースレッドが読み取っていない行数。
    var remaining: Int { lock.withLock { $0.count } }
}

/// `pre()` を繰り返しポンプして、リーダースレッドが注入したイベントが反映される
/// （条件成立）まで待つ。
@MainActor
private func pumpInjection(
    _ renderer: MetaphorRenderer,
    _ plugin: InputInjectionPlugin,
    until condition: () -> Bool,
    timeout: TimeInterval = 2.0
) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let cb = renderer.commandQueue.makeCommandBuffer() {
            plugin.pre(commandBuffer: cb, time: 0)
            cb.commit()
        }
        if condition() { return }
        Thread.sleep(forTimeInterval: 0.005)
    }
}

// MARK: - ライフサイクル

@Suite("Sketch lifecycle", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchLifecycleTests {

    @Test("setup() → compute() → draw() の順に各フレーム 1 回ずつ呼ばれる")
    func computeRunsBeforeDrawEachFrame() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.start()

        harness.renderer.renderFrame()
        harness.renderer.renderFrame()

        #expect(sketch.log == ["setup", "compute", "draw", "compute", "draw"],
                "setup() は最初のフレームより前に 1 回だけ、以降は毎フレーム compute → draw の順に 1 回ずつ: \(sketch.log)")
    }

    @Test("frameCount は draw の入口で加算され compute からは前フレーム値が見える")
    func frameCountAdvancesInDrawPhase() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.start()

        harness.renderer.renderFrame()
        harness.renderer.renderFrame()

        // compute は beginFrame より前なので「まだ加算されていない」値を見る。
        #expect(sketch.frameCountAtCompute == [0, 1],
                "compute は前フレームまでの frameCount を見る: \(sketch.frameCountAtCompute)")
        #expect(sketch.frameCountAtDraw == [1, 2],
                "draw は加算後の frameCount を見る: \(sketch.frameCountAtDraw)")
        #expect(harness.context.frameCount == 2)
    }

    @Test("compute と draw は同一フレームで同じ time / deltaTime を見る")
    func computeAndDrawShareTheFrameClock() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.start()

        harness.renderer.renderFrame()
        harness.renderer.renderFrame()

        #expect(sketch.clockAtCompute.count == 2)
        #expect(sketch.clockAtDraw.count == 2)
        for i in 0..<2 {
            // prevTime を更新するのは draw だけ。compute が更新すると draw の
            // deltaTime が 0 に潰れる（この不変条件を固定する）。
            #expect(sketch.clockAtCompute[i].time == sketch.clockAtDraw[i].time,
                    "frame \(i): time が compute/draw で一致すべき")
            #expect(sketch.clockAtCompute[i].delta == sketch.clockAtDraw[i].delta,
                    "frame \(i): deltaTime が compute/draw で一致すべき")
        }
        // 2 フレーム目の deltaTime は 1 フレーム目の time との差（累積時刻ではない）。
        let expectedDelta = sketch.clockAtDraw[1].time - sketch.clockAtDraw[0].time
        #expect(abs(sketch.clockAtDraw[1].delta - expectedDelta) < 1e-4,
                "2 フレーム目の deltaTime は前フレームからの差分: \(sketch.clockAtDraw[1].delta) vs \(expectedDelta)")
    }

    @Test("setup() 内の noLoop() は起動前にループ停止状態を確定する")
    func noLoopInSetupStopsTheLoop() throws {
        let sketch = RecordingSketch()
        sketch.setupBody = { $0.noLoop() }
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.start()

        // SketchRunner は startWindowedLoop / startHeadlessLoop でこの値を見て
        // 単一フレーム描画へ分岐する。
        #expect(!harness.context.isLooping, "setup() 内の noLoop() が反映されるべき")
        #expect(!sketch.isLooping, "Sketch 層からも停止状態が見える")
    }

    @Test("noLoop() / loop() は状態遷移時だけコールバックを発火する")
    func loopCallbacksFireOnTransitionOnly() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.start()

        sketch.noLoop()
        sketch.noLoop()
        #expect(harness.noLoopCalls == 1, "連続 noLoop() は 1 回だけ通知")
        #expect(!sketch.isLooping)

        sketch.loop()
        sketch.loop()
        #expect(harness.loopCalls == 1, "連続 loop() は 1 回だけ通知")
        #expect(sketch.isLooping)
    }

    @Test("redraw() は isLooping を変えずに毎回 onRedraw を発火する")
    func redrawDoesNotChangeLoopState() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.start()

        sketch.redraw()
        #expect(harness.redrawCalls == 1)
        #expect(sketch.isLooping, "ループ中の redraw() は状態を変えない")

        sketch.noLoop()
        sketch.redraw()
        sketch.redraw()
        #expect(harness.redrawCalls == 3, "noLoop 中でも毎回発火する")
        #expect(!sketch.isLooping, "redraw() は停止状態を解除しない")
        #expect(harness.loopCalls == 0, "redraw() は loop() を意味しない")
    }

    @Test("frameRate(_:) は指定値をそのまま転送する（0・負値も含む）")
    func frameRateForwardsValueVerbatim() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.start()

        sketch.frameRate(24)
        sketch.frameRate(120)
        // 境界: 転送段では値を加工しない（クランプ・検証はランナー側の責務）。
        // クランプは SketchRunner.handleFrameRate の入口で行う(#358)。
        sketch.frameRate(0)
        sketch.frameRate(-5)

        #expect(harness.frameRateCalls == [24, 120, 0, -5],
                "値も順序も加工されずに届く: \(harness.frameRateCalls)")
    }

    // 回帰テスト(#358): handleFrameRate のクランプ(max(fps, 1))が以前はタイマー経路の
    // interval 計算にしか掛かっておらず、renderer.targetFPS(→ Probe の frame.json)と
    // MTKView.preferredFramesPerSecond には 0 / 負値がそのまま渡っていた。
    // SketchRunnerHarness は onFrameRate を記録専用スタブに差し替えるため
    // handleFrameRate 自体は経由しない。実装を直接検証するため SketchRunner を
    // 単体構築し(NSApplication のランループには依存しないため可能)、
    // handleFrameRate(_:) を直接呼び出す。
    @Test("handleFrameRate はクランプ後の値を targetFPS と MTKView.preferredFramesPerSecond の両方へ渡す")
    func handleFrameRateClampsAllPaths() throws {
        let runner = SketchRunner()
        runner.renderer = try MetaphorRenderer(width: 64, height: 64)
        runner.mtkView = MetaphorMTKView()

        runner.handleFrameRate(0)
        #expect(runner.renderer?.targetFPS == 1, "targetFPS は 1 にクランプされるべき")
        #expect(runner.mtkView?.preferredFramesPerSecond == 1,
                "MTKView.preferredFramesPerSecond も 1 にクランプされるべき")

        runner.handleFrameRate(-5)
        #expect(runner.renderer?.targetFPS == 1)
        #expect(runner.mtkView?.preferredFramesPerSecond == 1)

        // 極端に大きい正の値は妥当な範囲(= 正の値)のまま素通しでよい。
        runner.handleFrameRate(1_000_000)
        #expect(runner.renderer?.targetFPS == 1_000_000)
        #expect(runner.mtkView?.preferredFramesPerSecond == 1_000_000)

        // 通常の正値は従来どおり素通し。
        runner.handleFrameRate(30)
        #expect(runner.renderer?.targetFPS == 30)
        #expect(runner.mtkView?.preferredFramesPerSecond == 30)
    }

    // 回帰テスト(#793): noLoop() で止めている間も時計（renderer.elapsedTime）は進むが
    // フレームは発火しないため、再開後の最初のフレームの deltaTime に「止めていた
    // 実時間まるごと」が乗っていた（0.8 秒止めれば 60fps の 54 倍）。
    // handleLoop() がフレーム再開の前に時計の起点を寄せ直すことを、
    // handleFrameRate と同じ形（SketchRunner を単体構築して直接呼ぶ）で確かめる。
    @Test("handleLoop は再開時にフレーム時刻の起点を現在時刻へ寄せ直す")
    func handleLoopResyncsFrameClock() throws {
        let runner = SketchRunner()
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        runner.renderer = renderer
        runner.mtkView = MetaphorMTKView()

        // t = 0 のフレームを描いた直後に noLoop() したとみなす。
        _ = runner.frameClock.advance(to: 0)
        #expect(runner.frameClock.previousTime == 0)

        // 止めている間に時計が 5 秒進んだ状況を作る（clockOffset は elapsedTime に乗る）。
        renderer.clockOffset = 5.0
        let elapsedAtResume = Float(renderer.elapsedTime)
        #expect(elapsedAtResume >= 5.0)

        runner.handleLoop()

        #expect(runner.frameClock.previousTime >= 5.0,
                "起点が 0 のままだと、再開後の最初の deltaTime に 5 秒が乗る")
        // 再開直後のフレーム（1/60 秒後）の deltaTime は 1 フレームぶんに収まる。
        let firstFrameDelta = runner.frameClock.advance(to: elapsedAtResume + 1.0 / 60)
        #expect(firstFrameDelta < 0.1, "実測 \(firstFrameDelta)s: 止めていた時間が乗っている")
    }

    @Test("制御コールバック未配線でも loop/noLoop/redraw/frameRate は no-op")
    func animationControlWithoutCallbacksIsSafe() throws {
        // 失敗系: SketchRunner が配線する前（あるいはテスト用の裸コンテキスト）でも
        // クラッシュせず、状態だけが変わる。
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let context = SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
        #expect(context.isLooping)

        context.redraw()          // onRedraw 未設定
        context.frameRate(30)     // onFrameRate 未設定
        context.noLoop()          // onNoLoop 未設定
        #expect(!context.isLooping, "コールバックが無くても状態は遷移する")
        context.loop()
        #expect(context.isLooping)
    }

    @Test("_commandBuffer は compute フェーズ中だけ有効")
    func commandBufferIsScopedToComputePhase() throws {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let context = SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
        #expect(context._commandBuffer == nil, "フェーズ外では nil")

        let cb = try #require(renderer.commandQueue.makeCommandBuffer())
        context.beginCompute(commandBuffer: cb, time: 1, deltaTime: 0.5)
        #expect(context._commandBuffer != nil, "compute フェーズ中は有効")
        #expect(context.time == 1)
        #expect(context.deltaTime == 0.5)

        context.endCompute()
        #expect(context._commandBuffer == nil, "endCompute でクリアされる")
        cb.commit()
    }
}

// MARK: - SketchConfig の反映

@Suite("SketchConfig reflection")
struct SketchConfigReflectionTests {

    @Test("既定値（syphon / fullScreen / renderLoopMode / msaa / plugins）")
    func remainingDefaults() {
        let config = SketchConfig()
        #expect(config.syphon == false, "Syphon はオプトイン")
        #expect(config.fullScreen == false)
        #expect(config.renderLoopMode == .displayLink)
        #expect(config.msaa == 4)
        #expect(config.plugins.isEmpty)
    }

    @Test("Sketch は config を上書きしなければ既定値を返す")
    func protocolDefaultConfig() async {
        await MainActor.run {
            let bare = DefaultConfigSketch()
            #expect(bare.config.width == SketchConfig().width)
            #expect(bare.config.height == SketchConfig().height)
            #expect(bare.config.title == SketchConfig().title)

            let custom = RecordingSketch()
            custom.configOverride = SketchConfig(width: 320, height: 240, title: "custom", fps: 24)
            #expect(custom.config.width == 320)
            #expect(custom.config.height == 240)
            #expect(custom.config.title == "custom")
            #expect(custom.config.fps == 24)
        }
    }

    @Test("RenderLoopMode の等価性（Syphon 自動切替の判定が依存する）")
    func renderLoopModeEquality() {
        // SketchRunner は `config.renderLoopMode == .displayLink` で
        // タイマーモードへの自動切替を判断する。
        #expect(RenderLoopMode.displayLink == .displayLink)
        #expect(RenderLoopMode.timer(fps: 60) != .displayLink)
        #expect(RenderLoopMode.timer(fps: 30) != RenderLoopMode.timer(fps: 60),
                "associated value の違いが等価性に効く")
        #expect(RenderLoopMode.timer(fps: 30) == RenderLoopMode.timer(fps: 30))
    }

    @Test("PluginFactory は呼び出しごとに新しいインスタンスを返す")
    func pluginFactoryCreatesFreshInstances() async {
        await MainActor.run {
            let factory = PluginFactory { MockPlugin(id: "factory-test") }
            let a = factory.create()
            let b = factory.create()
            #expect(a !== b, "SketchConfig は Sendable なのでプラグインは遅延生成される")
            #expect(a.pluginID == "factory-test")
            #expect(b.pluginID == "factory-test")
        }
    }
}

@Suite("SketchConfig → renderer", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchConfigRendererTests {

    @Test("config.width / height がレンダラ・キャンバス・コンテキストへ届く")
    func canvasSizeReflectsConfig() throws {
        // 非正方サイズで幅と高さの取り違えを検出する。
        let config = SketchConfig(width: 256, height: 128)
        let harness = try SketchRunnerHarness(sketch: RecordingSketch(), config: config)

        #expect(harness.renderer.textureManager.width == 256)
        #expect(harness.renderer.textureManager.height == 128)
        #expect(harness.context.width == 256)
        #expect(harness.context.height == 128)
        #expect(harness.context.canvas.width == 256)
        #expect(harness.context.canvas.height == 128)
        #expect(harness.sketch.width == 256, "Sketch 層からも同じ値が見える")
        #expect(harness.sketch.height == 128)
    }

    @Test("config.msaa がオフスクリーンテクスチャのサンプル数へ届く")
    func msaaReflectsConfig() throws {
        let harness = try SketchRunnerHarness(
            sketch: RecordingSketch(), config: SketchConfig(width: 64, height: 64, msaa: 1)
        )
        #expect(harness.renderer.textureManager.sampleCount == 1)

        // 4x MSAA は Apple Silicon で常に利用可能。
        let msaa4 = try SketchRunnerHarness(
            sketch: RecordingSketch(), config: SketchConfig(width: 64, height: 64, msaa: 4)
        )
        #expect(msaa4.renderer.textureManager.sampleCount == 4)
    }

    @Test("不正・非対応の msaa は 1 にフォールバックする")
    func msaaFallsBackToOne() throws {
        // 境界: 1 未満は無条件で 1。
        let zero = try SketchRunnerHarness(
            sketch: RecordingSketch(), config: SketchConfig(width: 64, height: 64, msaa: 0)
        )
        #expect(zero.renderer.textureManager.sampleCount == 1, "msaa=0 は 1 へ")

        // デバイスが非対応と答える値でもフォールバックする。
        let device = try #require(MetalTestHelper.device)
        let unsupported = [3, 5, 6, 7, 16, 32].first { !device.supportsTextureSampleCount($0) }
        let target = try #require(unsupported, "非対応サンプル数が見つからない")
        let harness = try SketchRunnerHarness(
            sketch: RecordingSketch(),
            config: SketchConfig(width: 64, height: 64, msaa: target)
        )
        #expect(harness.renderer.textureManager.sampleCount == 1,
                "非対応の msaa=\(target) は 1 へフォールバック")
    }

    @Test("config.plugins は setup() より前に登録され plugin(id:) で引ける")
    func configPluginsAreAvailableInSetup() throws {
        let sketch = RecordingSketch()
        var pluginIDInSetup: String??
        sketch.setupBody = { s in
            // setup() の時点でプラグインが引けることが config.plugins の契約。
            pluginIDInSetup = s._context?.renderer.plugin(id: "config-plugin")?.pluginID
        }

        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.start(plugins: [PluginFactory { MockPlugin(id: "config-plugin") }])

        #expect(pluginIDInSetup == "config-plugin",
                "setup() 内でプラグインが解決できるべき: \(String(describing: pluginIDInSetup))")

        let registered = try #require(
            harness.renderer.plugin(id: "config-plugin") as? MockPlugin
        )
        #expect(registered.attachedRenderer === harness.renderer)
        #expect(registered.attachedSketch === sketch, "sketch 付きで attach される")
        #expect(registered.startCallCount == 1, "notifyPluginsStart が届く")
    }
}

// MARK: - 入力イベント配送（InputInjectionPlugin 経由）

@Suite("Sketch input dispatch", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchInputDispatchTests {

    /// 入力注入プラグインを配線したハーネスを作る。
    private func makeInjectedHarness(
        _ lines: [String]
    ) throws -> (harness: SketchRunnerHarness, sketch: RecordingSketch, plugin: InputInjectionPlugin) {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.connectInput()
        harness.start()
        let feeder = EventLineFeeder(lines)
        let plugin = InputInjectionPlugin(lineSource: { feeder.next() })
        harness.renderer.addPlugin(plugin, sketch: sketch)
        return (harness, sketch, plugin)
    }

    @Test("mouseDown → mouseUp は pressed → released → clicked の順に届く")
    func mouseDownUpDeliversClick() throws {
        let (harness, sketch, plugin) = try makeInjectedHarness([
            #"{"t":"mouseDown","x":12.0,"y":34.0,"button":0}"#,
            #"{"t":"mouseUp","x":12.0,"y":34.0,"button":0}"#
        ])
        pumpInjection(harness.renderer, plugin, until: { sketch.log.contains("mouseClicked") })

        let events = sketch.log.filter { $0.hasPrefix("mouse") }
        #expect(events == ["mousePressed", "mouseReleased", "mouseClicked"],
                "ドラッグなしの押下→解放はクリックを生む: \(events)")
        #expect(sketch.mouseX == 12)
        #expect(sketch.mouseY == 34)
    }

    @Test("ドラッグを挟むと mouseClicked は発火しない")
    func dragSuppressesClick() throws {
        let (harness, sketch, plugin) = try makeInjectedHarness([
            #"{"t":"mouseDown","x":10.0,"y":10.0,"button":0}"#,
            #"{"t":"mouseDrag","x":40.0,"y":50.0}"#,
            #"{"t":"mouseUp","x":40.0,"y":50.0,"button":0}"#
        ])
        pumpInjection(harness.renderer, plugin, until: { sketch.log.contains("mouseReleased") })

        let events = sketch.log.filter { $0.hasPrefix("mouse") }
        #expect(events == ["mousePressed", "mouseDragged", "mouseReleased"],
                "ドラッグ後の解放はクリック扱いにしない: \(events)")
        #expect(!sketch.log.contains("mouseClicked"))
    }

    @Test("文字を生成するキーは keyPressed と keyTyped の両方を発火する")
    func characterKeyFiresKeyTyped() throws {
        let (harness, sketch, plugin) = try makeInjectedHarness([
            #"{"t":"keyDown","code":0,"chars":"a","repeat":false}"#
        ])
        pumpInjection(harness.renderer, plugin, until: { sketch.log.contains("keyPressed") })

        #expect(sketch.log.filter { $0.hasPrefix("key") } == ["keyPressed", "keyTyped"])
        #expect(sketch.key == "a", "Sketch 層の key に届く")
        #expect(sketch.keyCode == 0)
        #expect(sketch.isKeyPressed)
    }

    @Test("矢印キー（PUA 文字）は keyPressed だけで keyTyped は発火しない")
    func functionKeyDoesNotFireKeyTyped() throws {
        // 矢印キーは Unicode Private Use Area の文字として届く（上矢印 = U+F700）。
        // Processing 互換で keyTyped の対象外。
        let (harness, sketch, plugin) = try makeInjectedHarness([
            #"{"t":"keyDown","code":126,"chars":"\uf700","repeat":false}"#
        ])
        pumpInjection(harness.renderer, plugin, until: { sketch.log.contains("keyPressed") })

        #expect(sketch.log.filter { $0.hasPrefix("key") } == ["keyPressed"],
                "機能キーで keyTyped は呼ばれない: \(sketch.log)")
        #expect(sketch.isKeyDown(126))
    }

    @Test("keyUp は keyReleased を発火し押下集合から外す")
    func keyUpReleasesKey() throws {
        let (harness, sketch, plugin) = try makeInjectedHarness([
            #"{"t":"keyDown","code":49,"chars":" ","repeat":false}"#,
            #"{"t":"keyUp","code":49}"#
        ])
        pumpInjection(harness.renderer, plugin, until: { sketch.log.contains("keyReleased") })

        #expect(!sketch.isKeyDown(49), "解放後は押下集合から外れる")
        #expect(!sketch.isKeyPressed)
    }

    @Test("scroll はフレーム内で累積し updateFrame でリセットされる")
    func scrollAccumulatesWithinFrame() throws {
        let (harness, sketch, plugin) = try makeInjectedHarness([
            #"{"t":"scroll","dx":1.0,"dy":-2.0}"#,
            #"{"t":"scroll","dx":2.0,"dy":-3.0}"#
        ])
        pumpInjection(harness.renderer, plugin, until: { sketch.scrollY == -5 })

        #expect(sketch.scrollX == 3, "dx が累積する: \(sketch.scrollX)")
        #expect(sketch.scrollY == -5, "dy が累積する: \(sketch.scrollY)")
        #expect(sketch.log.filter { $0 == "mouseScrolled" }.count == 2)

        // 次フレーム頭（renderFrame → input.updateFrame）でゼロに戻る。
        harness.renderer.input.updateFrame()
        #expect(sketch.scrollX == 0)
        #expect(sketch.scrollY == 0)
    }

    @Test("フィールドが欠けた JSON は 0 既定で解釈される")
    func missingFieldsDefaultToZero() throws {
        // 境界: x/y/button を省略しても落とさず 0 として扱う（CONTRACT の既定値）。
        let (harness, sketch, plugin) = try makeInjectedHarness([
            #"{"t":"mouseMove","x":80.0,"y":90.0}"#,
            #"{"t":"mouseDown"}"#
        ])
        pumpInjection(harness.renderer, plugin, until: { sketch.log.contains("mousePressed") })

        #expect(sketch.mouseX == 0, "省略された x は 0")
        #expect(sketch.mouseY == 0, "省略された y は 0")
        #expect(sketch.mouseButton == .left, "省略された button は 0 = 左")
        #expect(sketch.isMousePressed)
    }

    @Test("ファイルドロップは Sketch.fileDropped(_:) へパスをそのまま届ける")
    func fileDropReachesSketch() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.connectInput()
        harness.start()

        harness.renderer.input.handleFileDrop(paths: ["/tmp/a.png", "/tmp/b.png"])

        #expect(sketch.log.contains("fileDropped"))
        #expect(sketch.droppedPaths == [["/tmp/a.png", "/tmp/b.png"]],
                "配列の内容と順序がそのまま届く: \(sketch.droppedPaths)")
    }

    @Test("detach 後に溜まったイベントを pre() で捌いてもクラッシュしない")
    func preAfterDetachIsSafe() throws {
        // 失敗系: onDetach 後（renderer が nil）に未処理イベントが残っていても、
        // 捨てるだけで InputManager には触らない。
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let feeder = EventLineFeeder([#"{"t":"mouseMove","x":5.0,"y":6.0}"#])
        let plugin = InputInjectionPlugin(lineSource: { feeder.next() })

        // attach でリーダースレッドが起動し、pre() を呼ばないのでキューに溜まる。
        renderer.addPlugin(plugin)
        let deadline = Date().addingTimeInterval(2.0)
        while feeder.remaining > 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        #expect(feeder.remaining == 0, "リーダースレッドが行を読み切っているべき")
        Thread.sleep(forTimeInterval: 0.05)  // enqueue の完了を待つ猶予

        plugin.onDetach()
        let cb = try #require(renderer.commandQueue.makeCommandBuffer())
        plugin.pre(commandBuffer: cb, time: 0)   // renderer は nil
        cb.commit()
        #expect(renderer.input.mouseX == 0, "detach 済みのプラグインは入力へ届かない")
    }

    // MARK: - pmouse のフレーム同期（#522）

    // pmouse は「1 フレーム前」であって 2 フレーム前ではない。イベントがフレームの
    // どこで処理されるかは経路によって違う（ヘッドレスの InputInjectionPlugin は
    // pre() = updateFrame() の後、AppKit はフレーム間）ので、両方を renderFrame() の
    // 実経路で回して確かめる。単体で InputManager を叩くだけでは配線を検証できない。

    @Test("pmouse は draw から見て 1 フレーム前を指す（イベントがフレーム頭の後に届く経路）")
    func pmouseIsOneFrameOldWithInFrameInjection() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.connectInput()
        harness.start()
        // ヘッドレス注入と同じく、フレーム頭（updateFrame）の後・draw の前に位置を進める。
        let feed = MouseFeedPlugin(positions: [10, 30, 60])
        harness.renderer.addPlugin(feed, sketch: sketch)

        harness.renderer.renderFrame()
        harness.renderer.renderFrame()
        harness.renderer.renderFrame()

        let seen = sketch.mouseAtDraw.map { [$0.pmouse, $0.mouse] }
        #expect(seen == [[0, 10], [10, 30], [30, 60]],
                "各フレームの pmouse は直前フレームの mouse: \(seen)")
    }

    @Test("pmouse は draw から見て 1 フレーム前を指す（イベントがフレーム頭の前に届く経路）")
    func pmouseIsOneFrameOldWithBetweenFrameEvents() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.connectInput()
        harness.start()
        let input = harness.renderer.input

        // AppKit と同じく、フレームとフレームの間（renderFrame の外）で位置が進む。
        input.handleMouseMoved(x: 10, y: 0)
        harness.renderer.renderFrame()
        input.handleMouseMoved(x: 30, y: 0)
        harness.renderer.renderFrame()
        input.handleMouseMoved(x: 60, y: 0)
        harness.renderer.renderFrame()

        let seen = sketch.mouseAtDraw.map { [$0.pmouse, $0.mouse] }
        #expect(seen == [[10, 10], [10, 30], [30, 60]],
                "1 フレーム目は前フレームが無いので pmouse == mouse: \(seen)")
    }
}

/// 各フレームの `pre()`（= `updateFrame()` の後、`draw()` の前）で
/// マウス位置を 1 つずつ進めるテスト用プラグイン。ヘッドレスの
/// ``InputInjectionPlugin`` と同じタイミングを、スレッドを挟まず決定的に再現する。
@MainActor
private final class MouseFeedPlugin: MetaphorPlugin {
    let pluginID = "test.mouse-feed"
    private var positions: [Float]
    private weak var renderer: MetaphorRenderer?

    init(positions: [Float]) {
        self.positions = positions
    }

    func onAttach(renderer: MetaphorRenderer) {
        self.renderer = renderer
    }

    func pre(commandBuffer: MTLCommandBuffer, time: Double) {
        guard !positions.isEmpty else { return }
        renderer?.input.handleMouseMoved(x: positions.removeFirst(), y: 0)
    }
}

// MARK: - keyTyped 判定（SketchRunner の純粋ロジック）

@Suite("keyTyped character gating")
struct ProducesCharacterTests {

    @Test("文字入力を生成するキーだけ true")
    func plainCharacters() {
        #expect(SketchRunner.producesCharacter("a"))
        #expect(SketchRunner.producesCharacter(" "))
        #expect(SketchRunner.producesCharacter("あ"))
        #expect(SketchRunner.producesCharacter("\u{8}"), "backspace も文字として届く")
    }

    @Test("nil・空文字は false")
    func emptyInputs() {
        #expect(!SketchRunner.producesCharacter(nil))
        #expect(!SketchRunner.producesCharacter(""))
    }

    @Test("Unicode Private Use Area U+F700–U+F8FF の境界")
    func privateUseAreaBoundaries() {
        // 機能キー（矢印・ファンクション）はこの範囲で届く。
        #expect(!SketchRunner.producesCharacter("\u{F700}"), "下端は除外")
        #expect(!SketchRunner.producesCharacter("\u{F8FF}"), "上端は除外")
        #expect(!SketchRunner.producesCharacter("\u{F702}"), "左矢印")
        #expect(SketchRunner.producesCharacter("\u{F6FF}"), "下端の 1 つ手前は文字扱い")
        #expect(SketchRunner.producesCharacter("\u{F900}"), "上端の 1 つ先は文字扱い")
    }
}

// MARK: - 二層 API（Sketch 拡張 → SketchContext）の対称性

@Suite("Two-layer API symmetry", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TwoLayerSymmetryTests {

    private func makeHarness(
        width: Int = 200, height: Int = 100
    ) throws -> SketchRunnerHarness {
        try SketchRunnerHarness(
            sketch: RecordingSketch(),
            config: SketchConfig(width: width, height: height)
        )
    }

    @Test("width / height は非正方キャンバスでも取り違えない")
    func dimensionsForwardInOrder() throws {
        let h = try makeHarness(width: 200, height: 100)
        #expect(h.sketch.width == h.context.width)
        #expect(h.sketch.height == h.context.height)
        #expect(h.sketch.width == 200)
        #expect(h.sketch.height == 100)
    }

    @Test("time / deltaTime / frameCount は context の値をそのまま返す")
    func clockPropertiesForward() throws {
        let h = try makeHarness()
        h.context.time = 1.25
        h.context.deltaTime = 0.5
        h.context.frameCount = 7

        #expect(h.sketch.time == 1.25)
        #expect(h.sketch.deltaTime == 0.5)
        #expect(h.sketch.frameCount == 7)
    }

    @Test("fill / stroke は 2D・3D 両方へ、strokeWeight は 2D のみへ届く")
    func styleFansOutPerADR0005() throws {
        let h = try makeHarness()
        // チャンネルごとに違う値を渡してチャンネル取り違えも検出する。
        h.sketch.fill(10, 20, 30, 40)
        h.sketch.stroke(50, 60, 70, 80)
        h.sketch.strokeWeight(7)

        let f = h.context.canvas.fillColor
        #expect(abs(f.x - 10.0 / 255) < 1e-5, "R")
        #expect(abs(f.y - 20.0 / 255) < 1e-5, "G")
        #expect(abs(f.z - 30.0 / 255) < 1e-5, "B")
        #expect(abs(f.w - 40.0 / 255) < 1e-5, "A")
        #expect(h.context.canvas3D.fillColor == f, "fill は 3D にも同じ値で届く")

        let s = h.context.canvas.strokeColor
        #expect(abs(s.x - 50.0 / 255) < 1e-5)
        #expect(h.context.canvas3D.strokeColor == s, "stroke も 3D へ届く")

        // ADR-0005: strokeWeight は 2D のみ（3D ワイヤーフレームには効かない）。
        #expect(h.context.canvas.currentStrokeWeight == 7)
    }

    @Test("noFill / noStroke は 2D・3D 両方へ届く")
    func noFillNoStrokeFanOut() throws {
        let h = try makeHarness()
        // 3D は hasStroke の既定が false なので、まず両方を有効にしてから消す。
        h.sketch.fill(1, 2, 3)
        h.sketch.stroke(4, 5, 6)
        #expect(h.context.canvas.hasFill && h.context.canvas3D.hasFill)
        #expect(h.context.canvas.hasStroke && h.context.canvas3D.hasStroke)

        h.sketch.noFill()
        h.sketch.noStroke()
        #expect(!h.context.canvas.hasFill)
        #expect(!h.context.canvas.hasStroke)
        #expect(!h.context.canvas3D.hasFill, "noFill は 3D にも届く")
        #expect(!h.context.canvas3D.hasStroke, "noStroke は 3D にも届く")
    }

    @Test("tint / noTint は 2D のみに作用する")
    func tintIsTwoDOnly() throws {
        let h = try makeHarness()
        #expect(!h.context.canvas.hasTint, "既定はティントなし")

        h.sketch.tint(255, 128, 0)
        #expect(h.context.canvas.hasTint)
        #expect(abs(h.context.canvas.tintColor.y - 128.0 / 255) < 1e-5,
                "第 2 チャンネルが G に入る")

        h.sketch.noTint()
        #expect(!h.context.canvas.hasTint)
    }

    @Test("rectMode / ellipseMode / imageMode は互いに干渉しない")
    func shapeModesAreIndependent() throws {
        let h = try makeHarness()
        h.sketch.rectMode(.center)
        h.sketch.ellipseMode(.corner)
        h.sketch.imageMode(.center)

        #expect(h.context.canvas.currentRectMode == .center)
        #expect(h.context.canvas.currentEllipseMode == .corner)
        #expect(h.context.canvas.currentImageMode == .center)
    }

    @Test("translate(x, y) は x / y を取り違えず変換へ反映される")
    func translateForwardsInOrder() throws {
        let h = try makeHarness()
        h.sketch.translate(30, 70)
        let t = h.context.canvas.currentTransform
        // float3x3 の平行移動成分は 3 列目。
        #expect(t[2].x == 30, "x: \(t[2].x)")
        #expect(t[2].y == 70, "y: \(t[2].y)")
    }

    @Test("push / pop は 2D・3D 両方の変換を保存・復元する")
    func pushPopRestoresBothCanvases() throws {
        let h = try makeHarness()
        let base2D = h.context.canvas.currentTransform
        let base3D = h.context.canvas3D.currentTransform

        h.sketch.push()
        h.sketch.translate(11, 22)
        h.sketch.translate(1, 2, 3)   // 3D 側
        #expect(h.context.canvas.currentTransform != base2D)
        #expect(h.context.canvas3D.currentTransform != base3D)

        h.sketch.pop()
        #expect(h.context.canvas.currentTransform == base2D, "2D が復元される")
        #expect(h.context.canvas3D.currentTransform == base3D, "3D も復元される")
    }

    @Test("screenX / screenY は screenPosition の対応成分と一致する")
    func screenAccessorsMatchScreenPosition() throws {
        let h = try makeHarness()
        // 非対称な変換にして x/y の取り違えを検出できるようにする。
        h.sketch.translate(30, 70)

        let p = h.context.screenPosition(5, 9)
        #expect(h.sketch.screenX(5, 9) == p.x)
        #expect(h.sketch.screenY(5, 9) == p.y)
        #expect(p.x != p.y, "x と y が別値の状況で比較している")

        let p3 = h.context.screenPosition(5, 9, 13)
        #expect(h.sketch.screenX(5, 9, 13) == p3.x)
        #expect(h.sketch.screenY(5, 9, 13) == p3.y)
        #expect(h.sketch.screenZ(5, 9, 13) == p3.z)
    }

    @Test("isInFront は canvas3D の判定へ 3 層とも同じ答えで届く (#824)")
    func isInFrontForwardsThroughAllLayers() throws {
        let h = try makeHarness()
        h.context.canvas3D.begin(encoder: nil, time: 0)
        let centerX = h.context.canvas3D.width / 2
        let centerY = h.context.canvas3D.height / 2
        let behindZ = h.context.canvas3D.cameraEye.z + 120

        // 前方・背後の両方で 3 層が一致することを見る（片方だけだと定数を返す
        // 実装でも通ってしまう）。
        #expect(h.sketch.isInFront(centerX, centerY, 0))
        #expect(h.context.isInFront(centerX, centerY, 0))
        #expect(h.context.canvas3D.isInFront(centerX, centerY, 0))

        #expect(h.sketch.isInFront(centerX, centerY, behindZ) == false)
        #expect(h.context.isInFront(centerX, centerY, behindZ) == false)
        #expect(h.context.canvas3D.isInFront(centerX, centerY, behindZ) == false)
    }

    @Test("createCanvas は (width, height) の順で転送される")
    func createCanvasForwardsInOrder() throws {
        let h = try makeHarness()
        h.sketch.createCanvas(width: 800, height: 600)
        #expect(h.createCanvasCalls.count == 1)
        #expect(h.createCanvasCalls.first?.width == 800)
        #expect(h.createCanvasCalls.first?.height == 600)
    }

    @Test("camera(eye:center:up:) は canvas3D のカメラ状態へ届く")
    func cameraForwardsToCanvas3D() throws {
        let h = try makeHarness()
        h.sketch.camera(
            eye: SIMD3(1, 2, 3), center: SIMD3(4, 5, 6), up: SIMD3(0, 0, 1)
        )
        #expect(h.context.canvas3D.cameraEye == SIMD3<Float>(1, 2, 3))
        #expect(h.context.canvas3D.cameraCenter == SIMD3<Float>(4, 5, 6))
        #expect(h.context.canvas3D.cameraUp == SIMD3<Float>(0, 0, 1))
    }

    @Test("perspective は fov / near / far をそのまま渡す")
    func perspectiveForwardsParameters() throws {
        let h = try makeHarness()
        h.sketch.perspective(fov: 1.1, near: 2.2, far: 3.3)
        #expect(h.context.canvas3D.fov == 1.1)
        #expect(h.context.canvas3D.nearPlane == 2.2)
        #expect(h.context.canvas3D.farPlane == 3.3)
        #expect(!h.context.canvas3D.useOrthographic)

        h.sketch.ortho()
        #expect(h.context.canvas3D.useOrthographic, "ortho() は投影方式を切り替える")
    }

    @Test("createVector は成分をそのまま持つベクトルを返す")
    func createVectorKeepsComponents() throws {
        let h = try makeHarness()
        let v2 = h.sketch.createVector(3, 4)
        #expect(v2 == Vec2(3, 4))
        let v3 = h.sketch.createVector(3, 4, 5)
        #expect(v3 == Vec3(3, 4, 5))
        #expect(h.sketch.createVector() == Vec2(0, 0), "既定は原点")
    }
}

// MARK: - 失敗系（context 未初期化・teardown 後）

@Suite("Sketch failure modes", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchFailureModeTests {

    @Test("起動前と teardown 後は _context が nil（描画 API の fatalError 分岐）")
    func contextIsNilBeforeStartAndAfterTeardown() throws {
        // `Sketch.context` は _context が nil のとき明示メッセージで fatalError する
        // （"Drawing APIs require an active SketchContext..."）。その分岐条件、つまり
        // 「SketchRunner の初期化前」と「teardown 後」を固定する。
        let sketch = RecordingSketch()
        #expect(sketch._context == nil, "SketchRunner の初期化前は context を持たない")

        let harness = try SketchRunnerHarness(sketch: sketch)
        #expect(sketch._context === harness.context)

        // applicationWillTerminate の teardown 経路（`sketchRef?._context = nil`）。
        sketch._context = nil
        #expect(sketch._context == nil, "teardown 後の描画 API 呼び出しも fatalError 対象")
    }

    @Test("probe() は context 未初期化でも無言 no-op（fatalError しない）")
    func probeWithoutContextIsSilentNoOp() {
        // 失敗モードの方針（Sketch.context の doc）: 描画系は fatalError、
        // 観測系の probe() は本体挙動を変えないよう無言 no-op。
        let sketch = RecordingSketch()
        #expect(sketch._context == nil)
        sketch.probe("count", 42)
        sketch.probe("label", "hello")
        sketch.probe("flag", true)
        sketch.probe("pos", SIMD2<Float>(1, 2))
        // クラッシュせずここへ到達できることが検証内容。
        #expect(sketch._context == nil)
    }

    @Test("probe() は probe プラグイン未登録なら no-op、登録済みなら記録する")
    func probeRecordsOnlyWithPlugin() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.start()

        // 未登録: 何も起きない（ホットパスに残して安全）。
        sketch.probe("particles.count", 3)
        #expect(harness.renderer.probePlugin == nil)

        // 登録後は同じ呼び出しが記録される（no-op テストが空振りでない証拠）。
        let plugin = MetaphorProbePlugin()
        harness.renderer.addPlugin(plugin, sketch: sketch)
        sketch.probe("particles.count", 3)
        sketch.probe("phase", "warmup")

        let snapshot = plugin.stateBuffer.snapshot()
        #expect(snapshot.count == 2, "probe した値だけが入る: \(snapshot.keys.sorted())")
        if case .int(let n) = snapshot["particles.count"] {
            #expect(n == 3)
        } else {
            Issue.record("particles.count が Int として記録されていない: \(String(describing: snapshot["particles.count"]))")
        }
        if case .string(let s) = snapshot["phase"] {
            #expect(s == "warmup")
        } else {
            Issue.record("phase が String として記録されていない")
        }
    }

    @Test("loadPixels() 前の pixels は空バッファ（読み取り系はクラッシュより空）")
    func pixelsBeforeLoadIsEmpty() throws {
        let sketch = RecordingSketch()
        let harness = try SketchRunnerHarness(sketch: sketch)
        harness.start()

        // 注: doc（Sketch.context）は「context 未初期化でも空バッファ」と読めるが、
        // 実際に空が返るのは context がある状態で loadPixels() 前のときだけ → Issue #356。
        let before = sketch.pixels
        #expect(before.count == 0, "loadPixels 前は空バッファ: count=\(before.count)")
        #expect(before.baseAddress == nil)

        // loadPixels 後は実バッファになる（空返しが恒久的な no-op でない証拠）。
        sketch.loadPixels()
        let after = sketch.pixels
        #expect(after.count == 64 * 64, "loadPixels 後はキャンバス分の要素数: \(after.count)")
    }
}
