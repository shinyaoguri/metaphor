import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

/// パフォーマンス HUD の見た目（Issue #574）。
///
/// HUD が「描かれているのに見えない」状態を防ぐ。チャンネル値をとる
/// `fill(_:_:_:_:)` は `colorMode`（既定の最大値 255）を通るため、0-1 の値で
/// 呼ぶとアルファが 1/255 になり事実上透明になる。
@Suite("PerformanceHUD Appearance", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct PerformanceHUDAppearanceTests {

    private func makeCanvas() throws -> Canvas2D {
        let device = MTLCreateSystemDefaultDevice()!
        return try Canvas2D(
            device: device,
            shaderLibrary: try ShaderLibrary(device: device),
            depthStencilCache: DepthStencilCache(device: device),
            width: 640,
            height: 360
        )
    }

    @Test("パネルと数字の色は見える濃さを持つ")
    func colorsAreVisible() {
        #expect(PerformanceHUD.panelColor.a > 0.5)
        #expect(PerformanceHUD.textColor.a == 1)
        #expect(PerformanceHUD.textColor.g == 1)
    }

    @Test("パネルの塗りが colorMode を通らずそのまま適用される")
    func panelStyleIgnoresColorMode() throws {
        let canvas = try makeCanvas()
        PerformanceHUD.applyPanelStyle(to: canvas)

        #expect(canvas.hasFill)
        #expect(canvas.fillColor == PerformanceHUD.panelColor.simd)
        // 0-1 の値をチャンネル指定で渡していたときのアルファ（0.6/255）に戻らないこと
        #expect(canvas.fillColor.w > 0.5)
    }

    @Test("数字の塗りはスケッチ側の colorMode に左右されない")
    func textStyleIgnoresColorMode() throws {
        let canvas = try makeCanvas()
        // スケッチが HSB 0-1 に切り替えていても HUD の色は変わらない
        canvas.colorMode(.hsb, 1)
        PerformanceHUD.applyTextStyle(to: canvas)

        #expect(canvas.fillColor == PerformanceHUD.textColor.simd)
    }
}


// MARK: - 採取経路（Issue #698）

/// HUD の fps / フレーム時間が ``FrameRateTracker`` の集計そのものであること（Issue #698）。
///
/// HUD は以前、独自の 60 サンプル単純平均から fps を出していた。同じ「実測 fps」を
/// 名乗る値が `Sketch.performance` / Probe の `frame.json` と食い違い得たので、
/// **同じ窓・同じ算出**へ寄せた。この Suite はその一致を固定する。
@Suite("PerformanceHUD Metrics")
@MainActor
struct PerformanceHUDMetricsTests {

    /// 実運用と同じ順序（毎フレーム record → その時刻で集計 → HUD 更新）で流し込む。
    /// - Returns: 最後のフレーム時刻。
    @discardableResult
    private func feed(
        hud: PerformanceHUD,
        tracker: FrameRateTracker,
        intervals: [Double],
        from start: Double = 100.0
    ) -> Double {
        var now = start
        tracker.record(at: now)
        hud.update(stats: tracker.windowStats(now: now))
        for interval in intervals {
            now += interval
            tracker.record(at: now)
            hud.update(stats: tracker.windowStats(now: now))
        }
        return now
    }

    /// 旧実装（直近 60 フレーム間隔の単純平均）の fps。窓が違うことを示すための参照値。
    private func legacyFPS(intervals: [Double], maxSamples: Int = 60) -> Float {
        let recent = intervals.suffix(maxSamples)
        let mean = recent.reduce(0, +) / Double(recent.count)
        return Float(1.0 / mean)
    }

    @Test("等間隔 16.67ms を積むと 60fps を表示する")
    func steadySixtyFPS() throws {
        let hud = PerformanceHUD()
        let tracker = FrameRateTracker()
        feed(hud: hud, tracker: tracker, intervals: Array(repeating: 1.0 / 60.0, count: 29))

        let fps = try #require(hud.fps)
        #expect(abs(fps - 60) < 0.5)
        let frameTime = try #require(hud.frameTime)
        #expect(abs(frameTime - 1000.0 / 60.0) < 0.1)
        #expect(hud.fpsText == "FPS: 60")
    }

    @Test("HUD の数字は performance.fps と同じ値になる")
    func matchesPerformanceSnapshot() {
        let hud = PerformanceHUD()
        let tracker = FrameRateTracker()
        let monitor = PerformanceMonitor(tracker: tracker)
        let now = feed(hud: hud, tracker: tracker, intervals: Array(repeating: 1.0 / 60.0, count: 40))

        let snapshot = monitor.snapshot(now: now, targetFPS: 60)
        #expect(hud.fps == snapshot.fps)
        #expect(hud.frameTime == snapshot.frameTimeMs?.mean)
    }

    @Test("スパイク混じりでも performance.fps と一致し続ける")
    func matchesPerformanceSnapshotWithSpikes() {
        let hud = PerformanceHUD()
        let tracker = FrameRateTracker()
        let monitor = PerformanceMonitor(tracker: tracker)
        // 1 フレームだけ 8 倍かかる（コンパイル・GC 等でよくある形）
        var intervals = Array(repeating: 1.0 / 60.0, count: 40)
        intervals[20] = 8.0 / 60.0
        let now = feed(hud: hud, tracker: tracker, intervals: intervals)

        let snapshot = monitor.snapshot(now: now, targetFPS: 60)
        #expect(hud.fps == snapshot.fps)
        #expect(hud.frameTime == snapshot.frameTimeMs?.mean)
    }

    /// 一致検査が空虚でないことの担保。旧実装の窓（直近 60 フレーム）と
    /// 新しい窓（直近 1 秒）は、レートが急変する系列で大きく食い違う。
    /// ここが差を検出できなくなったら、上の一致検査は「何も固定していない」。
    @Test("旧実装の 60 サンプル平均とは別の値になる（窓が違う）")
    func differsFromLegacyMovingAverage() throws {
        let hud = PerformanceHUD()
        let tracker = FrameRateTracker()
        // 重い区間（100ms × 30 = 3 秒）のあと軽い区間（5ms × 100 = 0.5 秒）
        let intervals = Array(repeating: 0.1, count: 30) + Array(repeating: 0.005, count: 100)
        feed(hud: hud, tracker: tracker, intervals: intervals)

        let fps = try #require(hud.fps)
        // 直近 1 秒には重い区間の尾が入るので 200fps にはならない
        #expect(abs(legacyFPS(intervals: intervals) - fps) > 50)
    }

    @Test("集計できないフレーム数では 0 ではなく -- を表示する")
    func showsDashesWhenUnavailable() {
        let hud = PerformanceHUD()
        let tracker = FrameRateTracker()

        // 起動直後（1 フレームしか無い）は算出不能
        tracker.record(at: 100)
        hud.update(stats: tracker.windowStats(now: 100))
        #expect(hud.fps == nil)
        #expect(hud.frameTime == nil)
        #expect(hud.fpsText == "FPS: --")
        #expect(hud.frameTimeText == "Frame: -- ms")

        // noLoop() 停止中（記録が窓の外へ出た）も同じ
        feed(hud: hud, tracker: tracker, intervals: Array(repeating: 1.0 / 60.0, count: 29), from: 101)
        #expect(hud.fps != nil)
        hud.update(stats: tracker.windowStats(now: 200))
        #expect(hud.fps == nil)
        #expect(hud.fpsText == "FPS: --")
    }

    @Test("GPU 時間はトラッカーではなくコマンドバッファの実測から出す")
    func gpuTimeStaysIndependent() {
        let hud = PerformanceHUD()
        hud.updateGPUTime(start: 10.0, end: 10.004)
        #expect(abs(hud.gpuTime - 4) < 0.001)
        #expect(hud.gpuTimeText == "GPU: 4.00 ms")

        // fps が算出不能でも GPU 時間は保持される
        hud.update(stats: nil)
        #expect(hud.gpuTimeText == "GPU: 4.00 ms")
    }
}
