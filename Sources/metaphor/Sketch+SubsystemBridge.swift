import MetaphorCore
import MetaphorAudio
import MetaphorVideo
import MetaphorPhysics

// MARK: - サブシステム自動管理ブリッジ
//
// 各補助モジュール（Audio / Video / Physics）は MetaphorCore に依存しない独立 Tier
// なので、`SketchSubsystem`（MetaphorCore 定義）への準拠はそれらを束ねるこの umbrella
// ターゲットで付与する。型もプロトコルも同一パッケージ内なので `@retroactive` は不要
// （付けると逆に警告 / Swift 6 ではエラーになる）。これにより `AutoSubsystemManager`
// に登録して毎フレームの更新を自動化できる（従来の手動 update()/step() もそのまま使える）。

extension AudioAnalyzer: SketchSubsystem {
    /// Per-frame FFT and beat analysis update. `deltaTime` is unused — the previous time is held internally.
    public func update(deltaTime: Float) { update() }
}

extension VideoPlayer: SketchSubsystem {
    /// Per-frame playback position and texture update.
    public func update(deltaTime: Float) { update() }
}

extension Physics2D: SketchSubsystem {
    /// Advances the physics by `deltaTime`. Real frame time always jitters, so it
    /// goes through the fixed-step accumulator (`advance`) rather than straight into
    /// `step(deltaTime)`. Verlet carries velocity as displacement per step, so a
    /// jittering dt pumps energy in and out and the same sketch moves differently
    /// from run to run and from machine to machine (#756).
    public func update(deltaTime: Float) { advance(deltaTime) }
}
