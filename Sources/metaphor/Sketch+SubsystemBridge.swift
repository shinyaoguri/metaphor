import MetaphorCore
import MetaphorAudio
import MetaphorVideo
import MetaphorPhysics

// MARK: - サブシステム自動管理ブリッジ
//
// 各補助モジュール（Audio / Video / Physics）は MetaphorCore に依存しない独立 Tier
// なので、`SketchSubsystem`（MetaphorCore 定義）への準拠はそれらを束ねるこの umbrella
// ターゲットで retroactive に付与する。これにより `AutoSubsystemManager` に登録して
// 毎フレームの更新を自動化できる（従来の手動 update()/step() もそのまま使える）。

extension AudioAnalyzer: @retroactive SketchSubsystem {
    /// 毎フレームの FFT/ビート解析更新。`deltaTime` は使わない（内部で前回時刻を持つ）。
    public func update(deltaTime: Float) { update() }
}

extension VideoPlayer: @retroactive SketchSubsystem {
    /// 毎フレームの再生位置/テクスチャ更新。
    public func update(deltaTime: Float) { update() }
}

extension Physics2D: @retroactive SketchSubsystem {
    /// 物理ステップを進める。`deltaTime` をそのままタイムステップに使う。
    public func update(deltaTime: Float) { step(deltaTime) }
}
