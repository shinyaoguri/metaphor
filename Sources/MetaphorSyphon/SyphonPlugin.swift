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
/// Not intended for direct use — library users normally do not instantiate this
/// directly; it is registered through the ``MetaphorRenderer/startSyphonServer(name:)`` compatibility facade.
@MainActor
public final class SyphonPlugin: MetaphorOutputPlugin {
    /// A stable plugin identifier. The facade (`startSyphonServer`/`stopSyphonServer`/
    /// `syphonOutput`) looks up the plugin by this ID.
    public static let id = "org.metaphor.syphon-output"

    public let pluginID: String

    /// The Syphon server name to publish (already resolved by the caller from env > config.syphonName > title, etc.).
    private let name: String

    /// The underlying ``SyphonOutput``. Created in `onAttach(renderer:)`, destroyed in `onDetach()`.
    public private(set) var output: SyphonOutput?

    /// - Parameter name: The Syphon server name (an already-resolved string).
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
