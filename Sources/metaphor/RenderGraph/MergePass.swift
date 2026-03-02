@preconcurrency import Metal

/// Blend the outputs of two upstream render passes into a single texture.
///
/// ``MergePass`` uses a compute shader to composite two input textures with
/// a configurable blend mode (add, alpha, multiply, or screen).
///
/// ```swift
/// let merged = try MergePass(scenePass, fxPass, blend: .add, device: device, shaderLibrary: shaderLibrary)
/// ```
@MainActor
public final class MergePass: RenderPassNode {
    // MARK: - Blend Type

    /// Define the blend mode used when merging two textures.
    public enum BlendType: String, CaseIterable, Sendable {
        /// Additive blending (A + B).
        case add
        /// Alpha compositing (B over A).
        case alpha
        /// Multiplicative blending (A * B).
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

    // MARK: - MergeParams (GPU struct)

    /// The parameters passed to the merge compute shader.
    private struct MergeParams {
        var blend_mode: UInt32
    }

    // MARK: - Public Properties

    /// The debug label identifying this merge pass.
    public let label: String

    /// The output texture after merging both inputs.
    public var output: MTLTexture?

    /// The blend mode used for compositing, which can be changed at runtime.
    public var blendType: BlendType

    // MARK: - Private Properties

    /// The base (background) render pass.
    private let passA: RenderPassNode

    /// The overlay (foreground) render pass.
    private let passB: RenderPassNode

    /// The Metal device used to create textures.
    private let device: MTLDevice

    /// The compute pipeline state for the merge shader.
    private let mergePipeline: MTLComputePipelineState

    /// The cached output texture, recreated when dimensions change.
    private var outputTexture: MTLTexture?

    /// The current width of the output texture.
    private var outputWidth: Int = 0

    /// The current height of the output texture.
    private var outputHeight: Int = 0

    // MARK: - Initialization

    /// Create a new merge pass that blends two upstream passes.
    ///
    /// - Parameters:
    ///   - a: The base (background layer) render pass.
    ///   - b: The overlay (foreground layer) render pass.
    ///   - blend: The blend mode for compositing.
    ///   - device: The Metal device used to create pipeline states and textures.
    ///   - shaderLibrary: The shader library providing the merge compute function.
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

        // Create the merge compute pipeline
        guard let function = shaderLibrary.function(
            named: MergeShaders.FunctionName.mergeTextures,
            from: ShaderLibrary.BuiltinKey.merge
        ) else {
            throw MergePassError.shaderNotFound(MergeShaders.FunctionName.mergeTextures)
        }
        self.mergePipeline = try PipelineFactory.buildCompute(device: device, function: function)
    }

    // MARK: - RenderPassNode

    /// Execute both input passes and merge their outputs using the blend mode.
    ///
    /// - Parameters:
    ///   - commandBuffer: The Metal command buffer to encode work into.
    ///   - time: The elapsed time in seconds.
    ///   - renderer: The ``MetaphorRenderer`` reference providing shared resources.
    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        // Execute input passes
        passA.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)
        passB.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)

        guard let texA = passA.output, let texB = passB.output else { return }

        // Size the output texture to the larger of the two inputs
        let w = max(texA.width, texB.width)
        let h = max(texA.height, texB.height)
        ensureOutputTexture(width: w, height: h)

        guard let outTex = outputTexture,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.label = "MergePass:\(label)"
        encoder.setComputePipelineState(mergePipeline)
        encoder.setTexture(texA, index: 0)
        encoder.setTexture(texB, index: 1)
        encoder.setTexture(outTex, index: 2)

        var params = MergeParams(blend_mode: blendType.rawIndex)
        encoder.setBytes(&params, length: MemoryLayout<MergeParams>.size, index: 0)

        // Calculate threadgroup size
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

    // MARK: - Private

    /// Ensure the output texture exists with the required dimensions, recreating it if needed.
    private func ensureOutputTexture(width: Int, height: Int) {
        guard width != outputWidth || height != outputHeight else { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
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

// MARK: - Error

/// Represent errors that can occur when creating a ``MergePass``.
enum MergePassError: Error {
    /// The required merge shader function was not found.
    case shaderNotFound(String)
}
