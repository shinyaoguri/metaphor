import Foundation

// MARK: - 実行時パフォーマンス（Issue #692）

extension SketchContext {
    /// 実測 fps・フレーム時間・メモリ・CPU・熱状態のスナップショット。
    ///
    /// 詳細は ``SketchPerformance`` を参照してください。
    public var performance: SketchPerformance {
        renderer.performanceMonitor.snapshot(targetFPS: renderer.targetFPS)
    }
}

extension Sketch {
    /// 実測 fps・フレーム時間・メモリ・CPU・熱状態のスナップショット。
    ///
    /// 「重くなったら自分で軽くする」（自己 degrade）を**外部プロセスに頼らずに**
    /// 書くための窓口です。常設展示のように誰も見ていない時間帯がある作品では、
    /// 劣化に自分で気づけることが基礎になります。
    ///
    /// ```swift
    /// func draw() {
    ///     // fps が落ちたら粒を減らす
    ///     if let fps = performance.fps, fps < 55 {
    ///         particleCount = max(2000, particleCount - 200)
    ///     }
    ///     // 熱が上がったら軽いシーンへ逃がす
    ///     if performance.thermalState == .serious { scene = .calm }
    /// }
    /// ```
    ///
    /// 値は Probe の `frame.json` の `performance`（CONTRACT.md 契約点 4）と同じ
    /// 採取経路・同じ意味論で、**Probe が有効かどうかとは無関係に読めます**。
    /// メモリと CPU は syscall を伴うため最短 0.5 秒間隔でしか更新されません
    /// （毎フレーム読んでも syscall は増えません）。
    public var performance: SketchPerformance {
        context.performance
    }
}
