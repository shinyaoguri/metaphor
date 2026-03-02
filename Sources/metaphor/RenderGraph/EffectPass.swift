@preconcurrency import Metal

/// エフェクトパス: 入力パスの出力にポストプロセスエフェクトチェーンを適用するノード
///
/// PostProcessPipeline を使い、入力テクスチャにエフェクトを順次適用する。
/// ```swift
/// let effect = try EffectPass(scenePass, effects: [.bloom(), .vignette()], device: device, shaderLibrary: shaderLibrary)
/// ```
@MainActor
public final class EffectPass: RenderPassNode {
    // MARK: - Public Properties

    public let label: String
    public var output: MTLTexture?

    /// エフェクトチェーン（実行時に変更可能）
    public var effects: [PostEffect] {
        get { pipeline.effects }
        set { pipeline.set(newValue) }
    }

    // MARK: - Private Properties

    private let inputPass: RenderPassNode
    private let pipeline: PostProcessPipeline

    // MARK: - Initialization

    /// 初期化
    /// - Parameters:
    ///   - input: 入力パスノード
    ///   - effects: 適用するポストプロセスエフェクト配列
    ///   - device: MTLDevice
    ///   - shaderLibrary: ShaderLibrary
    public init(
        _ input: RenderPassNode,
        effects: [PostEffect],
        device: MTLDevice,
        shaderLibrary: ShaderLibrary
    ) throws {
        self.label = "effect(\(input.label))"
        self.inputPass = input
        self.pipeline = try PostProcessPipeline(device: device, shaderLibrary: shaderLibrary)
        self.pipeline.set(effects)
    }

    // MARK: - RenderPassNode

    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        // まず入力パスを実行
        inputPass.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)

        guard let inputTexture = inputPass.output else { return }

        if pipeline.effects.isEmpty {
            // エフェクトがなければ入力をそのまま出力
            output = inputTexture
        } else {
            output = pipeline.apply(source: inputTexture, commandBuffer: commandBuffer)
        }
    }
}
