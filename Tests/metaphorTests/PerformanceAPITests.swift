import Foundation
import Metal
import MetaphorTestSupport
import Testing

@testable import MetaphorCore

/// スケッチから読める実行時パフォーマンス（Issue #692）。
///
/// 30 分の無人稼働で fps とメモリが劣化しないことは Probe を**外から**叩いて確かめる
/// しかなく、同じ値をスケッチ自身が読めなかった。「fps が落ちたら粒を減らす」といった
/// 自己 degrade が書けないため、Probe と同じ採取経路のまま公開 API にした。
@Suite("Sketch performance API")
@MainActor
struct PerformanceAPITests {

    /// 1 秒間 60fps 相当のフレーム時刻を流し込んだトラッカー。
    private func tracker(frames: Int = 60, interval: Double = 1.0 / 60, from: Double = 1000)
        -> FrameRateTracker {
        let tracker = FrameRateTracker()
        for i in 0..<frames {
            tracker.record(at: from + Double(i) * interval)
        }
        return tracker
    }

    // MARK: - fps / frameTime

    @Test("実測 fps とフレーム時間が Probe と同じ集計から出る")
    func fpsAndFrameTime() throws {
        let now = 1000 + 59.0 / 60
        let monitor = PerformanceMonitor(tracker: tracker())
        let snapshot = monitor.snapshot(now: now, targetFPS: 60)

        let fps = try #require(snapshot.fps)
        #expect(fps > 59.5 && fps < 60.5)
        let frameTime = try #require(snapshot.frameTimeMs)
        #expect(abs(frameTime.mean - 16.667) < 0.1)
        #expect(frameTime.max >= frameTime.mean)
        #expect(snapshot.targetFPS == 60)
    }

    @Test("フレームが足りないときは fps が nil（noLoop / 起動直後）")
    func fpsIsNilWithoutEnoughFrames() {
        let monitor = PerformanceMonitor(tracker: FrameRateTracker())
        let snapshot = monitor.snapshot(now: 1000, targetFPS: 60)
        #expect(snapshot.fps == nil)
        #expect(snapshot.frameTimeMs == nil)
        // 熱状態は常に読める（採取に失敗しないもの）。
        #expect(ThermalState.allCases.contains(snapshot.thermalState))
    }

    @Test("スパイクは frameTimeMs.max に出る")
    func spikeShowsUpInMax() throws {
        let tracker = FrameRateTracker()
        var t = 1000.0
        for _ in 0..<30 {
            tracker.record(at: t)
            t += 1.0 / 60
        }
        t += 0.05  // 50ms のスパイク
        tracker.record(at: t)

        let monitor = PerformanceMonitor(tracker: tracker)
        let frameTime = try #require(monitor.snapshot(now: t, targetFPS: 60).frameTimeMs)
        #expect(frameTime.max > 60)      // 16.7 + 50 ≒ 66.7ms
        #expect(frameTime.mean < 30)     // 平均はスパイクに埋もれない
    }

    // MARK: - syscall のキャッシュ

    @Test("メモリと CPU は最短間隔を空けてしか採り直さない")
    func processStatsAreCached() throws {
        let monitor = PerformanceMonitor(tracker: tracker(), minimumSampleInterval: 10)
        let first = monitor.snapshot(now: 1000, targetFPS: 60)
        #expect(try #require(first.memoryMB) > 0)

        // 間隔内では同じ値が返る（syscall を発行していない）。
        let second = monitor.snapshot(now: 1001, targetFPS: 60)
        #expect(second.memoryMB == first.memoryMB)
        #expect(second.cpuPercent == first.cpuPercent)

        // 間隔を跨げば採り直す（CPU は経過時間に依存するので、値そのものは比べない）。
        let third = monitor.snapshot(now: 1020, targetFPS: 60)
        #expect(third.memoryMB != nil)
    }

    @Test("Probe が無効でも読める（METAPHOR_PROBE は観測の窓口であって実行条件ではない)")
    func worksWithoutProbe() throws {
        try #require(MetalTestHelper.isGPUAvailable)
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        // Probe プラグインは登録していない。
        #expect(renderer.plugin(id: MetaphorProbePlugin.id) == nil)

        let snapshot = context.performance
        #expect(snapshot.targetFPS == renderer.targetFPS)
        #expect(snapshot.memoryMB != nil)
    }
}
