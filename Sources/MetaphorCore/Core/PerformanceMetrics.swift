import Foundation
import Darwin
import QuartzCore

/// 実測フレームレートの軽量トラッカー。
///
/// ``MetaphorRenderer/renderFrame()`` が毎フレーム ``record(at:)`` を呼び、
/// Probe リクエスト処理時（および ``Sketch/performance`` の読み出し時）に
/// ``windowStats(now:window:)`` で直近ウィンドウの実測 fps とフレーム時間を
/// 読み出します（Issue #271 / #692）。
///
/// ホットパス側（`record`）は固定長リングバッファへの書き込み 1 回だけで
/// アロケーションが無く、Probe の性能契約（ランタイム非侵害・Issue #118）を
/// 破りません。集計（`windowStats`）はリクエスト時のみ実行されます。
@MainActor
final class FrameRateTracker {
    /// リングバッファ容量。240fps で約 1 秒分（既定ウィンドウを満たす十分量）。
    /// これを超えるレートでは実効ウィンドウが短くなるだけで、値は正しいまま。
    private static let capacity = 240

    /// フレーム時刻のリングバッファ（単調増加が前提。`CACurrentMediaTime()` を渡す）。
    private var timestamps = [Double](repeating: 0, count: capacity)

    /// 次に書き込むスロット。
    private var head = 0

    /// 有効なエントリ数（`capacity` で飽和）。
    private var count = 0

    /// 直近ウィンドウの集計値。
    struct WindowStats {
        /// 実測フレームレート（フレーム間隔の実測から算出）。
        let fps: Double
        /// フレーム時間の平均（ミリ秒）。
        let frameTimeMeanMs: Double
        /// フレーム時間の最大（ミリ秒）。スパイク検出用。
        let frameTimeMaxMs: Double
    }

    /// フレームの開始時刻を記録します。毎フレーム 1 回呼びます。
    func record(at now: Double) {
        timestamps[head] = now
        head = (head + 1) % Self.capacity
        if count < Self.capacity { count += 1 }
    }

    /// `now` から遡って `window` 秒以内のフレーム時刻から実測 fps / フレーム時間を
    /// 集計します。ウィンドウ内のフレームが 2 個未満（noLoop 停止中・起動直後など）
    /// なら算出不能として `nil` を返します。
    func windowStats(now: Double, window: Double = 1.0) -> WindowStats? {
        guard count >= 2 else { return nil }
        let cutoff = now - window

        var first: Double?
        var last: Double = 0
        var prev: Double?
        var maxDelta: Double = 0
        var frames = 0

        // バッファは時系列順（古い→新しい）に走査する。ウィンドウ外の古い
        // エントリだけを読み飛ばせばよい（時刻は単調増加なので後続はすべて内側）。
        for i in 0..<count {
            let index = (head - count + i + Self.capacity) % Self.capacity
            let t = timestamps[index]
            guard t >= cutoff else { continue }
            if first == nil { first = t }
            if let prev {
                let delta = t - prev
                if delta > maxDelta { maxDelta = delta }
            }
            prev = t
            last = t
            frames += 1
        }

        guard let first, frames >= 2, last > first else { return nil }
        let span = last - first
        let intervals = Double(frames - 1)
        return WindowStats(
            fps: intervals / span,
            frameTimeMeanMs: span / intervals * 1000,
            frameTimeMaxMs: maxDelta * 1000
        )
    }
}

/// プロセス単位のリソース統計（メモリ footprint / CPU 使用率 / thermal state）を
/// syscall で取得するサンプラー（Issue #271）。
///
/// Probe リクエスト処理時のみ呼ぶ想定で、毎フレームの呼び出しは想定しません
/// （性能契約 #118: リクエストが無いフレームで syscall を発行しない）。
///
/// CPU 使用率は「前回サンプル時点との差分」で算出するため、呼び出し間の状態
/// （前回の累積 CPU 時間・時刻）を保持します。初回サンプルの起点は `init`
/// （＝プラグイン登録時）に取るため、初回リクエストでは「スケッチ起動から
/// リクエストまでの平均」が返ります。
@MainActor
final class ProcessStatsSampler {
    /// 前回サンプル時の累積 CPU 時間（秒）。
    private var lastCPUSeconds: Double?

    /// 前回サンプル時の wall clock（`CACurrentMediaTime()` 系の単調時刻、秒）。
    private var lastSampleTime: Double?

    init(now: Double) {
        // CPU 差分の起点を作る（初回リクエストを「起動からの平均」にするため）。
        lastCPUSeconds = Self.cumulativeCPUSeconds()
        lastSampleTime = now
    }

    /// 自タスクの Mach ポート。
    ///
    /// C の `mach_task_self()` はマクロで Swift からは呼べず、その実体である
    /// `mach_task_self_` は Swift からは**可変グローバル**に見えるため、strict
    /// concurrency が「共有可変状態」として警告する（新しい SDK では注釈が付いて
    /// いるが、最小サポートの Swift 5.10 SDK には無い）。値はカーネルが設定して以後
    /// 変化しないので、同じポートを返す `task_self_trap()` を一度だけ呼んで保持する。
    private static let selfTaskPort: mach_port_t = task_self_trap()

    /// 自プロセスの phys_footprint（MB）。Activity Monitor の「メモリ」に相当し、
    /// Malloc 断片・圧縮メモリを含む実効フットプリント。取得失敗時は `nil`。
    static func memoryFootprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(selfTaskPort, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// プロセスの累積 CPU 時間（user + system、秒）。取得失敗時は `nil`。
    ///
    /// `ri_user_time` / `ri_system_time` は Mach 時間単位のため
    /// `mach_timebase_info` で実時間へ変換します（Apple Silicon では 1:1 でない）。
    static func cumulativeCPUSeconds() -> Double? {
        var usage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard result == 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else {
            return nil
        }
        let ticks = usage.ri_user_time &+ usage.ri_system_time
        let nanos = Double(ticks) * Double(timebase.numer) / Double(timebase.denom)
        return nanos / 1_000_000_000
    }

    /// 前回サンプルからの平均 CPU 使用率（%）を返し、起点を今回に進めます。
    /// 1 コア = 100%（`top` / Activity Monitor 互換。マルチコア使用で 100 超あり）。
    /// 取得失敗・時間が進んでいない場合は `nil`。
    func cpuPercent(now: Double) -> Double? {
        guard let cpuNow = Self.cumulativeCPUSeconds() else { return nil }
        defer {
            lastCPUSeconds = cpuNow
            lastSampleTime = now
        }
        guard let lastCPU = lastCPUSeconds, let lastTime = lastSampleTime,
              now > lastTime else {
            return nil
        }
        return (cpuNow - lastCPU) / (now - lastTime) * 100
    }

    /// 現在の thermal state を frame.json の文字列表現で返します。
    static func thermalStateName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - 公開 API（Issue #692）

/// システムの熱状態。負荷を自分で落とす（自己 degrade）ときの判断材料です。
///
/// 意味論は `ProcessInfo.ThermalState` および Probe の wire format
/// （CONTRACT.md 契約点 4 の `performance.thermalState`）と同じです。
public enum ThermalState: String, Sendable, Codable, CaseIterable {
    /// 平常。
    case nominal
    /// やや上昇。ファンが回り始める程度。
    case fair
    /// 高い。システムが省電力へ寄せ始めるので、負荷を落とす頃合い。
    case serious
    /// 危険。表示を維持することより発熱を下げることが優先される。
    case critical
    /// 将来の OS が返す未知の状態。
    case unknown
}

/// スケッチ自身が読める実行時パフォーマンスの一式（Issue #692）。
///
/// 値は Probe の `frame.json` の `performance`（CONTRACT.md 契約点 4）と**同じ採取経路・
/// 同じ意味論**です。Probe が有効かどうかとは無関係に読めます（`METAPHOR_PROBE=1` は
/// 観測用の窓口であって、作品の実行条件ではありません）。
///
/// ```swift
/// func draw() {
///     if let fps = performance.fps, fps < 50 {
///         particleCount = max(1000, particleCount - 100)   // 自己 degrade
///     }
///     if performance.thermalState == .serious { ... }
/// }
/// ```
///
/// - Note: 採取にコストがある項目（``memoryMB`` / ``cpuPercent`` は syscall）は
///   最短 0.5 秒間隔でしか更新されません。毎フレーム読んでも syscall は増えません。
public struct SketchPerformance: Sendable {

    /// フレーム時間の統計（ミリ秒）。
    public struct FrameTime: Sendable {
        /// 直近ウィンドウの平均フレーム時間（ミリ秒）。
        public let mean: Float
        /// 直近ウィンドウの最大フレーム時間（ミリ秒）。スパイクの検出用。
        public let max: Float
    }

    /// 直近およそ 1 秒の**実測**フレームレート。
    ///
    /// 算出に足るフレームが無いとき（起動直後・`noLoop()` で停止中）は `nil`。
    /// 設定値ではなく実測値なので、``targetFPS`` と食い違うことがあります。
    public let fps: Float?

    /// 目標フレームレート（`frameRate()` / 環境変数 `METAPHOR_FPS` の解決結果）。
    public let targetFPS: Int

    /// 直近ウィンドウのフレーム時間。算出不能なときは `nil`。
    public let frameTimeMs: FrameTime?

    /// 自プロセスの phys_footprint（MB）。Activity Monitor の「メモリ」に相当します。
    /// 取得に失敗したときは `nil`。
    public let memoryMB: Float?

    /// 直近サンプルからの平均 CPU 使用率（%）。**1 コア = 100%** で、
    /// マルチコアを使い切ると 100 を超えます（`top` / Activity Monitor と同じ規約）。
    public let cpuPercent: Float?

    /// システムの熱状態。
    public let thermalState: ThermalState
}

/// ``SketchPerformance`` を組み立てるサンプラー（レンダラーが 1 つだけ持つ）。
///
/// fps とフレーム時間は ``FrameRateTracker`` から読むだけなのでコストがありません。
/// メモリと CPU は syscall を伴うため、**最短更新間隔**を設けてキャッシュします。
/// 毎フレーム `performance` を読むスケッチでも syscall は 0.5 秒に 1 回です
/// （Probe の性能契約 #118 と同じ考え方）。
///
/// Probe プラグインは自前の ``ProcessStatsSampler`` を持ち続けます。`cpuPercent` は
/// 「前回サンプルからの平均」という状態を持つため、サンプラーを共有すると
/// 「Probe が読んだ直後にスケッチが読む」ケースで極端に短い区間の値が返り、
/// どちらの値も不安定になるからです。実測コストは 0.5 秒に 1 回の syscall なので、
/// 経路を分けても実害はありません。
@MainActor
final class PerformanceMonitor {
    /// 実測 fps の供給元（レンダラーが毎フレーム更新しているもの）。
    private let tracker: FrameRateTracker

    /// syscall を伴う項目のサンプラー。初回読み出しまで作りません
    /// （`performance` を読まないスケッチにコストを負わせないため）。
    private var statsSampler: ProcessStatsSampler?

    /// 直近のサンプル（時刻・メモリ・CPU）。
    private var cachedAt: Double?
    private var cachedMemoryMB: Double?
    private var cachedCPUPercent: Double?

    /// syscall を伴う項目の最短更新間隔（秒）。
    private let minimumSampleInterval: Double

    init(tracker: FrameRateTracker, minimumSampleInterval: Double = 0.5) {
        self.tracker = tracker
        self.minimumSampleInterval = minimumSampleInterval
    }

    /// 現在のスナップショットを返します。
    func snapshot(now: Double = CACurrentMediaTime(), targetFPS: Int) -> SketchPerformance {
        let window = tracker.windowStats(now: now)
        refreshProcessStatsIfNeeded(now: now)
        return SketchPerformance(
            fps: window.map { Float($0.fps) },
            targetFPS: targetFPS,
            frameTimeMs: window.map {
                SketchPerformance.FrameTime(
                    mean: Float($0.frameTimeMeanMs), max: Float($0.frameTimeMaxMs)
                )
            },
            memoryMB: cachedMemoryMB.map(Float.init),
            cpuPercent: cachedCPUPercent.map(Float.init),
            thermalState: ThermalState(rawValue: ProcessStatsSampler.thermalStateName()) ?? .unknown
        )
    }

    /// 最短間隔を過ぎていれば syscall を発行して値を更新します。
    private func refreshProcessStatsIfNeeded(now: Double) {
        if let cachedAt, now - cachedAt < minimumSampleInterval { return }
        let sampler = statsSampler ?? ProcessStatsSampler(now: now)
        statsSampler = sampler
        cachedMemoryMB = ProcessStatsSampler.memoryFootprintMB()
        cachedCPUPercent = sampler.cpuPercent(now: now)
        cachedAt = now
    }
}
