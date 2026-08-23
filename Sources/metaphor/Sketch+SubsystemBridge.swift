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
    /// 毎フレームの FFT/ビート解析更新。`deltaTime` は使わない（内部で前回時刻を持つ）。
    public func update(deltaTime: Float) { update() }
}

extension VideoPlayer: SketchSubsystem {
    /// 毎フレームの再生位置/テクスチャ更新。
    public func update(deltaTime: Float) { update() }
}

extension Physics2D: SketchSubsystem {
    /// 物理を `deltaTime` ぶん進める。実フレーム時間は常に揺れるので、そのまま
    /// `step(deltaTime)` へ渡さず固定刻みのアキュムレータ（`advance`）を通す。
    /// Verlet の速度は「1 ステップあたりの変位」なので、dt が揺れるとエネルギーが
    /// 出入りし、同じスケッチが実行のたび・機械ごとに違う動きになる（#756）。
    public func update(deltaTime: Float) { advance(deltaTime) }
}
