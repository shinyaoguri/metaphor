@preconcurrency import Metal
import MetaphorCore

/// Blends the outputs of two upstream render passes into a single texture.
///
/// ``MergePass`` uses a compute shader to composite two input textures with a
/// configurable blend mode (add, alpha, multiply, screen).
///
/// ```swift
/// let merged = try MergePass(scenePass, fxPass, blend: .add, device: device, shaderLibrary: shaderLibrary)
/// ```
@MainActor
public final class MergePass: RenderPassNode {
    // MARK: - ブレンドタイプ

    /// Defines the blend mode used when merging two textures.
    public enum BlendType: String, CaseIterable, Sendable {
        /// Additive blending (A + B).
        case add
        /// Alpha compositing (B over A).
        case alpha
        /// Multiply blending (A * B).
        case multiply
        /// Screen blending (1 - (1-A) * (1-B)).
        case screen

        /// The raw index value passed to the merge compute shader.
        var rawIndex: UInt32 {
            switch self {
            case .add:      return 0
            case .alpha:    return 1
            case .multiply: return 2
            case .screen:   return 3
            }
        }
    }

    // MARK: - MergeParams（GPU 構造体）

    /// The parameters passed to the merge compute shader.
    private struct MergeParams {
        var blend_mode: UInt32
    }

    // MARK: - パブリックプロパティ

    /// A debug label that identifies this merge pass.
    public let label: String

    /// The output texture after merging both inputs.
    public var output: MTLTexture?

    /// The blend mode used for compositing. Can be changed at runtime.
    public var blendType: BlendType

    // MARK: - プライベートプロパティ

    /// The base (background) render pass.
    private let passA: RenderPassNode

    /// The overlay (foreground) render pass.
    private let passB: RenderPassNode

    /// The Metal device used to create textures.
    private let device: MTLDevice

    /// The compute pipeline state for the merge shader.
    private let mergePipeline: MTLComputePipelineState

    /// The cached output texture. Recreated when the size changes.
    private var outputTexture: MTLTexture?

    /// The current width of the output texture.
    private var outputWidth: Int = 0

    /// The current height of the output texture.
    private var outputHeight: Int = 0

    /// The frame token from the last time this node was executed (used to memoize against duplicate execution within a frame).
    /// The initial value `.max` is a "not yet executed" sentinel (`frameToken` starts at 0, so there is no collision).
    private var lastExecutedToken: UInt64 = .max

    // MARK: - 初期化

    /// Creates a new merge pass that blends two upstream passes.
    ///
    /// - Parameters:
    ///   - a: The base (background layer) render pass.
    ///   - b: The overlay (foreground layer) render pass.
    ///   - blend: The blend mode used for compositing.
    ///   - device: The Metal device used to create the pipeline state and textures.
    ///   - shaderLibrary: The shader library that provides the merge compute function.
    /// - Throws: An error if the merge shader cannot be found or pipeline creation fails.
    public init(
        _ a: RenderPassNode,
        _ b: RenderPassNode,
        blend: BlendType,
        device: MTLDevice,
        shaderLibrary: ShaderLibrary
    ) throws {
        self.label = "merge(\(a.label),\(b.label))"
        self.passA = a
        self.passB = b
        self.blendType = blend
        self.device = device

        // マージコンピュートパイプラインを作成
        guard let function = shaderLibrary.function(
            named: MergeShaders.FunctionName.mergeTextures,
            from: ShaderLibrary.BuiltinKey.merge
        ) else {
            throw MetaphorError.renderGraph(.shaderNotFound(MergeShaders.FunctionName.mergeTextures))
        }
        self.mergePipeline = try PipelineFactory.buildCompute(device: device, function: function)
    }

    // MARK: - RenderPassNode

    /// Executes both input passes and merges their output using the blend mode.
    ///
    /// - Parameters:
    ///   - commandBuffer: The Metal command buffer to encode the work into.
    ///   - time: The elapsed time, in seconds.
    ///   - renderer: A reference to the `MetaphorRenderer` that provides shared resources.
    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        // 同一フレーム内で既に実行済みなら、計算済みの output をそのまま使う。
        guard lastExecutedToken != renderer.frameToken else { return }
        lastExecutedToken = renderer.frameToken

        // 入力パスを実行
        passA.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)
        passB.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)

        guard let texA = passA.output, let texB = passB.output else { return }

        // 出力テクスチャを2つの入力の大きい方に合わせる
        // （フォーマットは texA に追従し、HDR 入力の暗黙量子化を避ける）
        let w = max(texA.width, texB.width)
        let h = max(texA.height, texB.height)
        ensureOutputTexture(width: w, height: h, pixelFormat: texA.pixelFormat)

        guard let outTex = outputTexture,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.label = "MergePass:\(label)"
        encoder.setComputePipelineState(mergePipeline)
        encoder.setTexture(texA, index: 0)
        encoder.setTexture(texB, index: 1)
        encoder.setTexture(outTex, index: 2)

        var params = MergeParams(blend_mode: blendType.rawIndex)
        encoder.setBytes(&params, length: MemoryLayout<MergeParams>.size, index: 0)

        // スレッドグループサイズを計算
        let threadWidth = mergePipeline.threadExecutionWidth
        let threadHeight = mergePipeline.maxTotalThreadsPerThreadgroup / threadWidth
        let threadsPerGroup = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        let threadgroups = MTLSize(
            width: (w + threadWidth - 1) / threadWidth,
            height: (h + threadHeight - 1) / threadHeight,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        output = outTex
    }

    // MARK: - プライベート

    /// Ensures an output texture of the required size and format exists, recreating it if necessary.
    private func ensureOutputTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) {
        guard width != outputWidth || height != outputHeight
                || outputTexture?.pixelFormat != pixelFormat else { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private

        outputTexture = device.makeTexture(descriptor: desc)
        outputTexture?.label = "metaphor.mergeOutput.\(label)"
        outputWidth = width
        outputHeight = height
    }
}
