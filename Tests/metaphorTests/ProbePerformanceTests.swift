import Foundation
import Testing
@testable import MetaphorCore

// MARK: - FrameRateTracker（#271）
//
// 時刻を注入して決定論的に検証する（実時間・GPU に依存しない）。

@Suite("FrameRateTracker")
@MainActor
struct FrameRateTrackerTests {

    /// `count` 個のフレームを `interval` 秒間隔で記録し、最後の時刻を返す。
    private func recordFrames(
        _ tracker: FrameRateTracker, count: Int, interval: Double, from start: Double = 100.0
    ) -> Double {
        var t = start
        for _ in 0..<count {
            tracker.record(at: t)
            t += interval
        }
        return t - interval
    }

    @Test("60fps 相当の時刻列から fps とフレーム時間を算出する")
    func steadySixtyFPS() {
        let tracker = FrameRateTracker()
        let interval = 1.0 / 60.0
        let last = recordFrames(tracker, count: 61, interval: interval)

        let stats = tracker.windowStats(now: last)
        #expect(stats != nil)
        guard let stats else { return }
        #expect(abs(stats.fps - 60.0) < 0.5)
        #expect(abs(stats.frameTimeMeanMs - interval * 1000) < 0.1)
        #expect(abs(stats.frameTimeMaxMs - interval * 1000) < 0.1)
    }

    @Test("フレーム時間のスパイクは max に現れ mean には均される")
    func spikeAppearsInMax() {
        let tracker = FrameRateTracker()
        // 60fps で 30 フレーム → 100ms のスパイク 1 回 → さらに 30 フレーム。
        var t = 100.0
        for _ in 0..<30 { tracker.record(at: t); t += 1.0 / 60.0 }
        t += 0.1 - 1.0 / 60.0  // スパイク: このフレームだけ 100ms
        for _ in 0..<30 { tracker.record(at: t); t += 1.0 / 60.0 }

        let stats = tracker.windowStats(now: t - 1.0 / 60.0)
        #expect(stats != nil)
        guard let stats else { return }
        #expect(abs(stats.frameTimeMaxMs - 100.0) < 0.5)
        #expect(stats.frameTimeMeanMs < 25.0)
        #expect(stats.fps < 60.0)
    }

    @Test("ウィンドウ外の古いフレームは集計から除外される")
    func excludesFramesOutsideWindow() {
        let tracker = FrameRateTracker()
        // 10fps で 1 秒分（古い）→ 2 秒の空白 → 60fps で 0.5 秒分（新しい）。
        var t = 100.0
        for _ in 0..<10 { tracker.record(at: t); t += 0.1 }
        t += 2.0
        for _ in 0..<30 { tracker.record(at: t); t += 1.0 / 60.0 }
        let last = t - 1.0 / 60.0

        let stats = tracker.windowStats(now: last)
        #expect(stats != nil)
        guard let stats else { return }
        // 古い 10fps 区間が混ざると fps は大きく下がる。60 近傍なら除外できている。
        #expect(abs(stats.fps - 60.0) < 1.0)
        #expect(stats.frameTimeMaxMs < 20.0)
    }

    @Test("フレームが 2 個未満なら nil（起動直後）")
    func returnsNilWithFewerThanTwoFrames() {
        let tracker = FrameRateTracker()
        #expect(tracker.windowStats(now: 100.0) == nil)
        tracker.record(at: 100.0)
        #expect(tracker.windowStats(now: 100.0) == nil)
        tracker.record(at: 100.1)
        #expect(tracker.windowStats(now: 100.1) != nil)
    }

    @Test("ウィンドウ内が 1 フレーム以下なら nil（noLoop 停止中）")
    func returnsNilWhenWindowHasOneFrame() {
        let tracker = FrameRateTracker()
        _ = recordFrames(tracker, count: 60, interval: 1.0 / 60.0)
        // 最後のフレームから 5 秒後 = 全フレームがウィンドウ外。
        #expect(tracker.windowStats(now: 105.0) == nil)
    }

    @Test("リングバッファ容量を超えても直近ウィンドウを正しく集計する")
    func ringBufferWrapAround() {
        let tracker = FrameRateTracker()
        // 容量 240 を大きく超える 1000 フレームを 120fps で記録。
        let last = recordFrames(tracker, count: 1000, interval: 1.0 / 120.0)

        let stats = tracker.windowStats(now: last)
        #expect(stats != nil)
        guard let stats else { return }
        #expect(abs(stats.fps - 120.0) < 1.0)
    }
}

// MARK: - ProcessStatsSampler（#271）
//
// syscall の値は環境依存のためスモークに留める（正の値・既知 enum・差分の健全性）。

@Suite("ProcessStatsSampler")
@MainActor
struct ProcessStatsSamplerTests {

    @Test("memoryFootprintMB は正の値を返す")
    func memoryFootprintIsPositive() {
        let mb = ProcessStatsSampler.memoryFootprintMB()
        #expect(mb != nil)
        #expect((mb ?? 0) > 0)
    }

    @Test("cumulativeCPUSeconds は正の値を返す")
    func cumulativeCPUIsPositive() {
        let seconds = ProcessStatsSampler.cumulativeCPUSeconds()
        #expect(seconds != nil)
        #expect((seconds ?? 0) > 0)
    }

    @Test("thermalStateName は契約の enum のいずれかを返す")
    func thermalStateIsKnown() {
        let known = ["nominal", "fair", "serious", "critical", "unknown"]
        #expect(known.contains(ProcessStatsSampler.thermalStateName()))
    }

    @Test("cpuPercent は非負を返し、起点を進める")
    func cpuPercentProgression() {
        let sampler = ProcessStatsSampler(now: 100.0)
        // 少し CPU を使う（差分がゼロ秒にならないよう軽いループ）。
        var sink = 0.0
        for i in 0..<200_000 { sink += Double(i).squareRoot() }
        #expect(sink > 0)

        let first = sampler.cpuPercent(now: 101.0)
        #expect(first != nil)
        #expect((first ?? -1) >= 0)

        // 2 回目: 起点が前回に進んでいる（同じ now では時間が進まず nil）。
        #expect(sampler.cpuPercent(now: 101.0) == nil)
        #expect((sampler.cpuPercent(now: 102.0) ?? -1) >= 0)
    }
}

// MARK: - Performance の encode（optional キー省略）

@Suite("ProbeFrameMetadata.Performance encoding")
struct ProbePerformanceEncodingTests {

    @Test("nil の optional フィールドはキー自体が省略される")
    func optionalFieldsAreOmitted() throws {
        let performance = ProbeFrameMetadata.Performance(
            fps: nil,
            targetFPS: 60,
            frameTimeMs: nil,
            memoryMB: nil,
            cpuPercent: nil,
            thermalState: "nominal"
        )
        let data = try JSONEncoder().encode(performance)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == ["targetFPS", "thermalState"])
    }
}
