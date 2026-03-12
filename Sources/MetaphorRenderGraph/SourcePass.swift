@preconcurrency import Metal
import MetaphorCore

/// Provide an offscreen render target where user code draws content.
///
/// ``SourcePass`` owns a dedicated `TextureManager` and exposes an
/// ``onDraw`` callback where user rendering code is executed. The resulting
/// color texture becomes the node's output.
///
/// ```swift
/// let pass = try SourcePass(label: "scene", device: device, width: 1920, height: 1080)
/// pass.onDraw = { encoder, time in
///     // Metal rendering code
/// }
/// ```
@MainActor
public final class SourcePass: RenderPassNode {
    // MARK: - Public Properties

    /// The debug label identifying this source pass.
    public let label: String

    /// The output color texture produced by this pass.
    public var output: MTLTexture? { textureManager.colorTexture }

    /// The draw callback invoked during execution.
    ///
    /// - Parameters:
    ///   - encoder: The render command encoder for the offscreen render target.
    ///   - time: The elapsed time in seconds.
    public var onDraw: ((MTLRenderCommandEncoder, Double) -> Void)?

    // MARK: - Private Properties

    /// The offscreen texture manager providing render targets.
    let textureManager: TextureManager

    // MARK: - Initialization

    /// Create a new source pass with a dedicated offscreen render target.
    ///
    /// - Parameters:
    ///   - label: The debug label for this pass.
    ///   - device: The Metal device used to create textures.
    ///   - width: The width of the offscreen texture in pixels.
    ///   - height: The height of the offscreen texture in pixels.
    ///   - sampleCount: The MSAA sample count (defaults to 1 for post-process compatibility).
    /// - Throws: An error if texture creation fails.
    public init(
        label: String,
        device: MTLDevice,
        width: Int,
        height: Int,
        sampleCount: Int = 1
    ) throws {
        self.label = label
        self.textureManager = try TextureManager(
            device: device,
            width: width,
            height: height,
            sampleCount: sampleCount
        )
    }

    // MARK: - RenderPassNode

    /// Execute the source pass by creating a render encoder and invoking the draw callback.
    ///
    /// - Parameters:
    ///   - commandBuffer: The Metal command buffer to encode work into.
    ///   - time: The elapsed time in seconds.
    ///   - renderer: The `MetaphorRenderer` reference (unused by source passes).
    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: textureManager.renderPassDescriptor
        ) else { return }
        encoder.label = "SourcePass:\(label)"
        onDraw?(encoder, time)
        encoder.endEncoding()
    }
}
