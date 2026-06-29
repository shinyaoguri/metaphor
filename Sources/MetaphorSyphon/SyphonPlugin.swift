import Metal
import MetaphorCore

/// 最終フレームを Syphon サーバー経由で publish する内部出力プラグイン。
///
/// `MetaphorOutputPlugin` に準拠するため、`post()` は他の全プラグインの `post()` の後
/// （出力フェーズ）に実行され、常に最終テクスチャを publish できます。
///
/// `SyphonMetalServer` は `onAttach(renderer:)` のタイミングで生成します（`onStart` では
/// ありません）。これは `noLoop()` でループが止まってもサーバーを生かし続ける従来挙動と
/// 一致させるためです（停止後も最後のフレームが MadMapper 等に残る）。サーバーの破棄は
/// `onDetach()`（= `removePlugin` / `renderer.shutdown()`）で行います。
///
/// 通常はライブラリ利用者が直接生成せず、``MetaphorRenderer/startSyphonServer(name:)``
/// の互換 facade 経由で登録されます。
@MainActor
public final class SyphonPlugin: MetaphorOutputPlugin {
    /// 安定したプラグイン識別子。facade（`startSyphonServer`/`stopSyphonServer`/
    /// `syphonOutput`）がこの ID でプラグインを検索します。
    public static let id = "org.metaphor.syphon-output"

    public let pluginID: String

    /// 公開する Syphon サーバー名（呼び出し側が env > config.syphonName > title 等で解決済み）。
    private let name: String

    /// 実体の ``SyphonOutput``。`onAttach(renderer:)` で生成、`onDetach()` で破棄。
    public private(set) var output: SyphonOutput?

    /// - Parameter name: Syphon サーバー名（解決済みの文字列）。
    public init(name: String) {
        self.pluginID = Self.id
        self.name = name
    }

    // MARK: - Lifecycle

    public func onAttach(renderer: MetaphorRenderer) {
        // サーバーは attach 時に生成（onStart ではない）。noLoop でも生存させる。
        output = SyphonOutput(device: renderer.device, name: name)
    }

    public func onDetach() {
        output?.stop()
        output = nil
    }

    // MARK: - Output phase

    public func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        // 従来のハードコード publish と同じく flipped: true を堅持（CLI/MadMapper 受信側が
        // この向きを前提にしているため）。
        output?.publish(texture: texture, commandBuffer: commandBuffer, flipped: true)
    }
}
