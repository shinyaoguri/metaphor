import Metal
import MetaphorCore

/// Applies a chain of post-process effects to the output of an upstream render pass.
///
/// ``EffectPass`` wraps a `PostProcessPipeline` and applies it to the input
/// node's output texture. If the effect list is empty, the input texture
/// passes through unchanged.
///
/// ```swift
/// let effect = try EffectPass(
///     scenePass, effects: [BloomEffect(), VignetteEffect()],
///     device: device, commandQueue: commandQueue, shaderLibrary: shaderLibrary
/// )
/// ```
@MainActor
public final class EffectPass: RenderPassNode {
    // MARK: - パブリックプロパティ

    /// A debug label that identifies this effect pass.
    public let label: String

    /// The output texture after effects have been applied.
    public var output: MTLTexture?

    /// The chain of post-process effects to apply.
    ///
    /// This property can be changed at runtime to swap the effect chain.
    public var effects: [any PostEffect] {
        get { pipeline.effects }
        set { pipeline.set(newValue) }
    }

    // MARK: - プライベートプロパティ

    /// The upstream render pass that provides the input texture.
    private let inputPass: RenderPassNode

    /// The post-process pipeline that applies the effects.
    private let pipeline: PostProcessPipeline

    /// The frame token from the last time this node was executed (used to memoize against duplicate execution within a frame).
    /// The initial value `.max` is a "not yet executed" sentinel (`frameToken` starts at 0, so there is no collision).
    private var lastExecutedToken: UInt64 = .max

    // MARK: - 初期化

    /// Creates a new effect pass that processes an upstream node's output.
    ///
    /// - Parameters:
    ///   - input: The upstream render pass node whose output is processed.
    ///   - effects: An array of post-process effects to apply in order.
    ///   - device: The Metal device used to create the pipeline state.
    ///   - commandQueue: The Metal command queue used for internal operations.
    ///   - shaderLibrary: The shader library that provides the effect shader functions.
    /// - Throws: ``MetaphorCore/MetaphorError/shaderNotFound(_:)`` when the built-in
    ///   full-screen blit vertex function is missing from the shader library.
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

    /// Executes the input pass and applies the effect chain to its output.
    ///
    /// - Parameters:
    ///   - commandBuffer: The Metal command buffer to encode the work into.
    ///   - time: The elapsed time, in seconds.
    ///   - renderer: A reference to the `MetaphorRenderer` that provides shared resources.
    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        // 同一フレーム内で既に実行済みなら、計算済みの output をそのまま使う。
        guard lastExecutedToken != renderer.frameToken else { return }
        lastExecutedToken = renderer.frameToken

        // まず入力パスを実行
        inputPass.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)

        guard let inputTexture = inputPass.output else { return }

        if pipeline.effects.isEmpty {
            // エフェクトが設定されていない場合は入力をそのまま通過
            output = inputTexture
        } else {
            output = pipeline.apply(source: inputTexture, commandBuffer: commandBuffer)
        }
    }
}
