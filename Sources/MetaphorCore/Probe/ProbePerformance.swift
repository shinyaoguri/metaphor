import Foundation
import Darwin

/// 実測フレームレートの軽量トラッカー。
///
/// ``MetaphorRenderer/renderFrame()`` が毎フレーム ``record(at:)`` を呼び、
/// Probe リクエスト処理時に ``windowStats(now:window:)`` で直近ウィンドウの
/// 実測 fps とフレーム時間を読み出します（Issue #271）。
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

    /// 自プロセスの phys_footprint（MB）。Activity Monitor の「メモリ」に相当し、
    /// Malloc 断片・圧縮メモリを含む実効フットプリント。取得失敗時は `nil`。
    static func memoryFootprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
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
