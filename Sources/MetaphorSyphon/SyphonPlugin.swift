import Metal
import MetaphorCore

/// An internal output plugin that publishes the final frame via a Syphon server.
///
/// Because this conforms to `MetaphorOutputPlugin`, its `post()` runs after every
/// other plugin's `post()` (the output phase), so it can always publish the final texture.
///
/// `SyphonMetalServer` is created at `onAttach(renderer:)` time (not `onStart`). This
/// matches the traditional behavior of keeping the server alive even after `noLoop()`
/// stops the loop (the last frame remains visible in MadMapper and similar clients
/// after stopping). The server is destroyed in `onDetach()` (= `removePlugin` / `renderer.shutdown()`).
///
/// Not part of the public API (ADR-0007 Decision 6 / #388): `internal` に退避済み。
/// 利用者はこれを直接生成せず、`MetaphorRenderer.startSyphonServer(name:)` 互換 facade か
/// `SketchConfig(syphon:)` / `METAPHOR_SYPHON_NAME` 経由の自動配線を使う。
@MainActor
final class SyphonPlugin: MetaphorOutputPlugin {
    /// A stable plugin identifier. The facade (`startSyphonServer`/`stopSyphonServer`/
    /// `syphonOutput`) looks up the plugin by this ID.
    static let id = "org.metaphor.syphon-output"

    let pluginID: String

    /// The Syphon server name to publish (already resolved by the caller from env > config.syphonName > title, etc.).
    private let name: String

    /// The underlying ``SyphonOutput``. Created in `onAttach(renderer:)`, destroyed in `onDetach()`.
    private(set) var output: SyphonOutput?

    /// - Parameter name: The Syphon server name (an already-resolved string).
    init(name: String) {
        self.pluginID = Self.id
        self.name = name
    }

    // MARK: - Lifecycle

    func onAttach(renderer: MetaphorRenderer) {
        // サーバーは attach 時に生成（onStart ではない）。noLoop でも生存させる。
        output = SyphonOutput(device: renderer.device, name: name)
    }

    func onDetach() {
        output?.stop()
        output = nil
    }

    // MARK: - Output phase

    func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        // 従来のハードコード publish と同じく flipped: true を堅持（CLI/MadMapper 受信側が
        // この向きを前提にしているため）。
        output?.publish(texture: texture, commandBuffer: commandBuffer, flipped: true)
    }
}
