@preconcurrency import Metal
import MetaphorCore

/// Apply a chain of post-process effects to the output of an upstream render pass.
///
/// ``EffectPass`` wraps a ``PostProcessPipeline`` and applies it to the input
/// node's output texture. If the effect list is empty, the input texture is
/// passed through unchanged.
///
/// ```swift
/// let effect = try EffectPass(scenePass, effects: [.bloom(), .vignette()], device: device, shaderLibrary: shaderLibrary)
/// ```
@MainActor
public final class EffectPass: RenderPassNode {
    // MARK: - Public Properties

    /// The debug label identifying this effect pass.
    public let label: String

    /// The output texture after effects have been applied.
    public var output: MTLTexture?

    /// The chain of post-process effects to apply.
    ///
    /// This property can be modified at runtime to change the effect chain.
    public var effects: [any PostEffect] {
        get { pipeline.effects }
        set { pipeline.set(newValue) }
    }

    // MARK: - Private Properties

    /// The upstream render pass providing the input texture.
    private let inputPass: RenderPassNode

    /// The post-process pipeline that applies the effects.
    private let pipeline: PostProcessPipeline

    // MARK: - Initialization

    /// Create a new effect pass that processes the output of an upstream node.
    ///
    /// - Parameters:
    ///   - input: The upstream render pass node whose output is processed.
    ///   - effects: The array of post-process effects to apply in order.
    ///   - device: The Metal device used to create pipeline states.
    ///   - commandQueue: The Metal command queue for internal operations.
    ///   - shaderLibrary: The shader library providing effect shader functions.
    /// - Throws: An error if pipeline creation fails.
    public init(
        _ input: RenderPassNode,
        effects: [any PostEffect],
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        shaderLibrary: ShaderLibrary
    ) throws {
        self.label = "effect(\(input.label))"
        self.inputPass = input
        self.pipeline = try PostProcessPipeline(device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary)
        self.pipeline.set(effects)
    }

    // MARK: - RenderPassNode

    /// Execute the input pass, then apply the effect chain to its output.
    ///
    /// - Parameters:
    ///   - commandBuffer: The Metal command buffer to encode work into.
    ///   - time: The elapsed time in seconds.
    ///   - renderer: The ``MetaphorRenderer`` reference providing shared resources.
    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        // Execute the input pass first
        inputPass.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)

        guard let inputTexture = inputPass.output else { return }

        if pipeline.effects.isEmpty {
            // Pass through input directly when no effects are configured
            output = inputTexture
        } else {
            output = pipeline.apply(source: inputTexture, commandBuffer: commandBuffer)
        }
    }
}
