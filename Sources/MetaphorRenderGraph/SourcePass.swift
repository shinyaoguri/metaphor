@preconcurrency import Metal
import MetaphorCore

/// Provides an offscreen render target that user code draws content into.
///
/// ``SourcePass`` holds a dedicated `TextureManager` and exposes the ``onDraw``
/// callback in which user rendering code runs.
/// The resulting color texture becomes the node's output.
///
/// ```swift
/// let pass = try SourcePass(label: "scene", device: device, width: 1920, height: 1080)
/// pass.onDraw = { encoder, time in
///     // Metal rendering code
/// }
/// ```
@MainActor
public final class SourcePass: RenderPassNode {
    // MARK: - パブリックプロパティ

    /// A debug label that identifies this source pass.
    public let label: String

    /// The output color texture produced by this pass.
    public var output: MTLTexture? { textureManager.colorTexture }

    /// The draw callback invoked on execution.
    ///
    /// - Parameters:
    ///   - encoder: The render command encoder for the offscreen render target.
    ///   - time: The elapsed time, in seconds.
    public var onDraw: ((MTLRenderCommandEncoder, Double) -> Void)?

    // MARK: - プライベートプロパティ

    /// The offscreen texture manager that provides the render target.
    let textureManager: TextureManager

    /// The frame token from the last time this node was executed (used to memoize against duplicate execution within a frame).
    ///
    /// The initial value is `.max`, representing "not yet executed". Since `frameToken`
    /// starts at 0, calling `execute` directly on a renderer that has never run
    /// `renderFrame()` (`frameToken == 0`) still always executes on the first call.
    private var lastExecutedToken: UInt64 = .max

    // MARK: - 初期化

    /// Creates a new source pass with a dedicated offscreen render target.
    ///
    /// - Parameters:
    ///   - label: A debug label for this pass.
    ///   - device: The Metal device used to create the texture.
    ///   - width: The offscreen texture width, in pixels.
    ///   - height: The offscreen texture height, in pixels.
    ///   - sampleCount: The MSAA sample count (defaults to 1 for post-processing compatibility).
    /// - Throws: ``MetaphorCore/MetaphorError/textureCreationFailed(width:height:format:)``
    ///   when the offscreen render target cannot be created.
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

    /// Creates a render encoder and invokes the draw callback to execute the source pass.
    ///
    /// - Parameters:
    ///   - commandBuffer: The Metal command buffer to encode the work into.
    ///   - time: The elapsed time, in seconds.
    ///   - renderer: A reference to `MetaphorRenderer` (unused by source passes).
    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        // 同一フレーム内で既に実行済みなら再実行しない。
        // 共有ノードが diamond 構造（例: MergePass(scene, EffectPass(scene))）で
        // 複数回到達されても onDraw は1フレーム1回に保たれる。
        guard lastExecutedToken != renderer.frameToken else { return }
        lastExecutedToken = renderer.frameToken

        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: textureManager.renderPassDescriptor
        ) else { return }
        encoder.label = "SourcePass:\(label)"
        onDraw?(encoder, time)
        encoder.endEncoding()
    }
}
