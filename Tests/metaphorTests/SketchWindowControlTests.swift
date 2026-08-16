import Testing

@testable import MetaphorCore
import MetaphorTestSupport

// このファイルは `SketchWindow`（セカンダリ窓経路）の制御 API の配線を固定する（#857）。
//
// `SketchContext` の loop() / noLoop() / redraw() / frameRate() / createCanvas() は、
// ハンドラが nil なら状態だけ変えて黙って返る。`SketchWindow.init` はレンダーコールバック
// （onDraw / onAfterDraw / onRecordFrame / onReplayMain）しか繋いでおらず、この経路では
// 5 本とも no-op に落ちていた。#808 / #828 が `SketchView` 経路で塞いだのと同じ穴の 3 経路目。
//
// 非ヘッドレスは `makeKeyAndOrderFront` で画面にウィンドウが出るため構築しない
// （`SketchWindowHeadlessTests` / `SketchWindowClockTests` と同じ方針）。つまりここで見るのは
// 常に **タイマー駆動**の経路 = `SketchView` の写経（`MTKView.isPaused` /
// `preferredFramesPerSecond`）では塞がらない側になる。ディスプレイリンク側の分岐は
// `SketchRunner.handleLoop` / `handleNoLoop` と同じ形で、そちらは既存のテストが見ている。

/// 描画クロージャの呼び出し回数を数える箱。
private final class DrawCounter: @unchecked Sendable {
    private(set) var count = 0

    @MainActor
    func record(_ ctx: SketchContext) {
        count += 1
    }
}

@Suite("セカンダリウィンドウの制御 API", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SketchWindowControlTests {

    private func makeWindow(
        width: Int = 32, height: Int = 32, fps: Int = 60, title: String
    ) throws -> SketchWindow {
        try SketchWindow(
            config: SketchWindowConfig(width: width, height: height, title: title, fps: fps),
            sharedResources: try SharedMetalResources(),
            isHeadless: true
        )
    }

    // MARK: - loop() / noLoop()

    // 回帰テスト(#857): 未配線だと isLooping だけ false になり、タイマーは回り続けていた。
    @Test("noLoop() はタイマー駆動のフレームを止め、loop() で再開する")
    func noLoopStopsTimerAndLoopResumes() async throws {
        let window = try makeWindow(title: "control-noloop")
        defer { window.close() }

        let drawn = DrawCounter()
        window.onDraw { drawn.record($0) }

        try await Task.sleep(nanoseconds: 300_000_000)
        try #require(drawn.count > 0, "まずフレームが回っていること（既定 60fps）")

        window.context.noLoop()
        #expect(window.context.isLooping == false)

        // suspend の直前に main へ積まれた 1 発が残りうるので、数え始める前に流し切る。
        try await Task.sleep(nanoseconds: 100_000_000)
        let stopped = drawn.count
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(
            drawn.count == stopped,
            "実測 +\(drawn.count - stopped) フレーム: 未配線だと isLooping だけ false になり回り続ける(#857)"
        )

        window.context.loop()
        #expect(window.context.isLooping == true)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(drawn.count > stopped, "loop() でタイマーが再開していない")
    }

    // 回帰テスト(#793 と同じ跳ね): 時計は止めている間も進むので、再開前に deltaTime の
    // 起点を寄せ直さないと、再開後の最初のフレームへ「止めていた実時間まるごと」が渡る。
    @Test("loop() で再開した直後の deltaTime に止めていた実時間が乗らない")
    func loopResyncsDeltaTime() async throws {
        let window = try makeWindow(title: "control-loop-resync")
        defer { window.close() }

        // 跳ねは 1 フレームにしか出ないので、最後の値ではなく最大値で見る。
        final class MaxDelta: @unchecked Sendable {
            private(set) var value: Float = 0
            func observe(_ dt: Float) { value = max(value, dt) }
            func reset() { value = 0 }
        }
        let delta = MaxDelta()
        window.onDraw { delta.observe($0.deltaTime) }

        try await Task.sleep(nanoseconds: 200_000_000)
        window.context.noLoop()
        try await Task.sleep(nanoseconds: 100_000_000)

        // 止めている間に時計が 5 秒進んだ状況を作る（clockOffset は elapsedTime に乗る）。
        delta.reset()
        window.context.renderer.clockOffset = 5.0
        window.context.loop()
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(delta.value < 0.5, "実測 \(delta.value)s: 止めていた 5 秒が deltaTime に乗っている")
    }

    // MARK: - redraw()

    // 回帰テスト(#857): redraw() は未配線では完全に無反応だった。
    @Test("redraw() は停止中でも draw クロージャをちょうど 1 回走らせる")
    func redrawRunsExactlyOneFrame() async throws {
        let window = try makeWindow(title: "control-redraw")
        defer { window.close() }

        let drawn = DrawCounter()
        window.onDraw { drawn.record($0) }

        window.context.noLoop()
        try await Task.sleep(nanoseconds: 200_000_000)
        let before = drawn.count

        window.context.redraw()

        #expect(
            drawn.count == before + 1,
            "実測 \(drawn.count - before) フレーム: 0 なら未配線、2 以上なら二重描画"
        )
    }

    // MARK: - frameRate()

    // 境界値(#358 と同じクランプ) + タイマー経路の本体。
    // `SketchView` の写経（preferredFramesPerSecond だけ）ではタイマーは 60fps のまま回る。
    @Test("frameRate() は 0 以下を 1 へクランプし、タイマーもその間隔へ張り替える")
    func frameRateClampsAndReschedulesTimer() async throws {
        let window = try makeWindow(title: "control-framerate")
        defer { window.close() }

        let drawn = DrawCounter()
        window.onDraw { drawn.record($0) }

        window.context.frameRate(0)
        #expect(window.context.renderer.targetFPS == 1, "0 以下は 1 へクランプするべき")

        // 張り替えたタイマーは `deadline: .now()` で 1 枚すぐ描き、次は 1 秒後。
        // 未配線なら 60fps のまま回るので 500ms で 30 枚前後になる。
        try await Task.sleep(nanoseconds: 150_000_000)
        let after = drawn.count
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(
            drawn.count - after <= 2,
            "実測 +\(drawn.count - after) フレーム: 60fps のままならタイマーを張り替えていない(#857)"
        )

        window.context.frameRate(30)
        #expect(window.context.renderer.targetFPS == 30, "正の値は素通し")

        window.context.frameRate(-5)
        #expect(window.context.renderer.targetFPS == 1, "負値も 1 へクランプするべき")
    }

    // MARK: - createCanvas()

    // 回帰テスト(#857): 未配線だと寸法もテクスチャも動かない。
    @Test("createCanvas() が ctx の寸法とオフスクリーンテクスチャの両方を作り替える")
    func createCanvasResizesContextAndTextures() throws {
        let window = try makeWindow(width: 64, height: 64, title: "control-createcanvas")
        defer { window.close() }

        window.context.createCanvas(width: 128, height: 32)

        #expect(window.context.width == 128, "実測 \(window.context.width): 64 のままなら未配線(#857)")
        #expect(window.context.height == 32, "実測 \(window.context.height): 64 のままなら未配線(#857)")

        // ctx の数値だけ書き換えて終わっていないこと。Syphon 出力やブリットは
        // textureManager 側の寸法・比率を見るので、ここが動かないと絵は元のままになる。
        let textures = window.context.renderer.textureManager
        #expect(textures.width == 128)
        #expect(textures.height == 32)
        #expect(textures.aspectRatio == 4.0)
    }

    // 境界: resizeCanvas はインフライトフレームを枯らすため inflightSemaphore を 3 つ
    // 取りに行き、取れないと 5 秒待って警告して進む。窓の外（＝この窓の描画クロージャの
    // 中ではない場所）から呼ぶ通常の使い方でそこに嵌まらないことを押さえる。
    @Test("回っている窓へ createCanvas() してもインフライトフレームで待たされない")
    func createCanvasDoesNotStallOnInflightFrames() async throws {
        let window = try makeWindow(width: 64, height: 64, title: "control-createcanvas-stall")
        defer { window.close() }

        window.onDraw { _ in }
        try await Task.sleep(nanoseconds: 200_000_000)

        let started = ContinuousClock.now
        window.context.createCanvas(width: 96, height: 96)
        let elapsed = ContinuousClock.now - started

        #expect(elapsed < .seconds(2.5), "実測 \(elapsed): 5 秒級ならセマフォを取り切れていない")
        #expect(window.context.width == 96)
    }

    // MARK: - teardown

    // 回帰テスト: noLoop() でタイマーを suspend したまま close() すると、
    // suspend された DispatchSource の解放で落ちる（cancel だけでは足りず resume が要る）。
    // 壊れているとこのテストはプロセスごと落ちるので、失敗は #expect ではなく
    // クラッシュとして現れる（`SketchRunner.applicationWillTerminate` と同じ性質）。
    @Test("noLoop() で止めたウィンドウを閉じてもクラッシュしない")
    func closingAfterNoLoopDoesNotCrash() async throws {
        let window = try makeWindow(title: "control-close-after-noloop")

        window.context.noLoop()
        try await Task.sleep(nanoseconds: 100_000_000)

        window.close()

        #expect(window.isOpen == false)
    }
}
