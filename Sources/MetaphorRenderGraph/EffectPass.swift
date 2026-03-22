@preconcurrency import Metal
import MetaphorCore

/// 上流レンダーパスの出力にポストプロセスエフェクトチェーンを適用します。
///
/// ``EffectPass`` は `PostProcessPipeline` をラップし、入力ノードの
/// 出力テクスチャに適用します。エフェクトリストが空の場合、
/// 入力テクスチャはそのまま通過します。
///
/// ```swift
/// let effect = try EffectPass(scenePass, effects: [.bloom(), .vignette()], device: device, shaderLibrary: shaderLibrary)
/// ```
@MainActor
public final class EffectPass: RenderPassNode {
    // MARK: - パブリックプロパティ

    /// このエフェクトパスを識別するデバッグラベル。
    public let label: String

    /// エフェクト適用後の出力テクスチャ。
    public var output: MTLTexture?

    /// 適用するポストプロセスエフェクトのチェーン。
    ///
    /// このプロパティは実行時に変更してエフェクトチェーンを切り替えることができます。
    public var effects: [any PostEffect] {
        get { pipeline.effects }
        set { pipeline.set(newValue) }
    }

    // MARK: - プライベートプロパティ

    /// 入力テクスチャを提供する上流レンダーパス。
    private let inputPass: RenderPassNode

    /// エフェクトを適用するポストプロセスパイプライン。
    private let pipeline: PostProcessPipeline

    // MARK: - 初期化

    /// 上流ノードの出力を処理する新しいエフェクトパスを作成します。
    ///
    /// - Parameters:
    ///   - input: 出力が処理される上流レンダーパスノード。
    ///   - effects: 順番に適用するポストプロセスエフェクトの配列。
    ///   - device: パイプラインステート作成に使用する Metal デバイス。
    ///   - commandQueue: 内部操作用の Metal コマンドキュー。
    ///   - shaderLibrary: エフェクトシェーダー関数を提供するシェーダーライブラリ。
    /// - Throws: パイプライン作成に失敗した場合にエラーをスローします。
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

    /// 入力パスを実行し、その出力にエフェクトチェーンを適用します。
    ///
    /// - Parameters:
    ///   - commandBuffer: 処理をエンコードする Metal コマンドバッファ。
    ///   - time: 経過時間（秒）。
    ///   - renderer: 共有リソースを提供する `MetaphorRenderer` 参照。
    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
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
