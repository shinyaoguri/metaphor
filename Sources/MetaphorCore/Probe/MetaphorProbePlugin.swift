import Foundation
import Metal

/// AI エージェント向けの観測プラグイン。
///
/// 通常フレームではゼロコスト相当のフックのみを実行し、外部からのリクエストが
/// あったときだけ最終オフスクリーンテクスチャを PNG として書き出します。
/// 同じ瞬間のフレームメタデータ（フレーム番号、サイズ、ユーザー定義値）も
/// `frame.json` に並べて出力するため、AI は「見た目」と「内部状態」の
/// 両方を観測できます。
///
/// 有効化は次の 2 通り。
/// - 環境変数 `METAPHOR_PROBE=1` を設定（自動登録）
/// - `SketchConfig(plugins: [PluginFactory { MetaphorProbePlugin() }])` で明示登録
///
/// 通常時のオーバーヘッドはリクエストファイルの mtime を確認するだけなので、
/// 描画パスには触れません。
@MainActor
public final class MetaphorProbePlugin: MetaphorPlugin {
    public static let id = "org.metaphor.probe"

    public let pluginID = MetaphorProbePlugin.id

    /// プラグイン設定。
    public let config: MetaphorProbeConfig

    /// 接続中のスケッチへの弱参照。
    weak var sketch: (any Sketch)?

    public init(config: MetaphorProbeConfig = MetaphorProbeConfig()) {
        self.config = config
    }

    // MARK: - Lifecycle

    public func onAttach(sketch: any Sketch) {
        self.sketch = sketch
    }

    public func onDetach() {
        self.sketch = nil
    }

    // MARK: - Frame hooks (Phase 1: stubs)

    public func pre(commandBuffer: MTLCommandBuffer, time: Double) {
        // Phase 2 でリクエストファイルの mtime を確認してフラグを立てる
    }

    public func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        // Phase 2 でフラグが立っているフレームだけ blit + PNG 書き出し
    }
}
