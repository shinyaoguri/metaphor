@preconcurrency import Metal
import MetaphorCore

/// 2つの上流レンダーパスの出力を1つのテクスチャにブレンドします。
///
/// ``MergePass`` はコンピュートシェーダーを使用して2つの入力テクスチャを
/// 設定可能なブレンドモード（add、alpha、multiply、screen）で合成します。
///
/// ```swift
/// let merged = try MergePass(scenePass, fxPass, blend: .add, device: device, shaderLibrary: shaderLibrary)
/// ```
@MainActor
public final class MergePass: RenderPassNode {
    // MARK: - ブレンドタイプ

    /// 2つのテクスチャをマージする際に使用するブレンドモードを定義します。
    public enum BlendType: String, CaseIterable, Sendable {
        /// 加算ブレンディング（A + B）。
        case add
        /// アルファ合成（B over A）。
        case alpha
        /// 乗算ブレンディング（A * B）。
        case multiply
        /// スクリーンブレンディング（1 - (1-A) * (1-B)）。
        case screen

        /// マージコンピュートシェーダーに渡される生のインデックス値。
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

    /// マージコンピュートシェーダーに渡されるパラメータ。
    private struct MergeParams {
        var blend_mode: UInt32
    }

    // MARK: - パブリックプロパティ

    /// このマージパスを識別するデバッグラベル。
    public let label: String

    /// 両入力をマージした後の出力テクスチャ。
    public var output: MTLTexture?

    /// 合成に使用するブレンドモード。実行時に変更可能です。
    public var blendType: BlendType

    // MARK: - プライベートプロパティ

    /// ベース（背景）レンダーパス。
    private let passA: RenderPassNode

    /// オーバーレイ（前景）レンダーパス。
    private let passB: RenderPassNode

    /// テクスチャ作成に使用する Metal デバイス。
    private let device: MTLDevice

    /// マージシェーダーのコンピュートパイプラインステート。
    private let mergePipeline: MTLComputePipelineState

    /// キャッシュ済み出力テクスチャ。サイズ変更時に再作成されます。
    private var outputTexture: MTLTexture?

    /// 出力テクスチャの現在の幅。
    private var outputWidth: Int = 0

    /// 出力テクスチャの現在の高さ。
    private var outputHeight: Int = 0

    // MARK: - 初期化

    /// 2つの上流パスをブレンドする新しいマージパスを作成します。
    ///
    /// - Parameters:
    ///   - a: ベース（背景レイヤー）レンダーパス。
    ///   - b: オーバーレイ（前景レイヤー）レンダーパス。
    ///   - blend: 合成用のブレンドモード。
    ///   - device: パイプラインステートとテクスチャの作成に使用する Metal デバイス。
    ///   - shaderLibrary: マージコンピュート関数を提供するシェーダーライブラリ。
    /// - Throws: マージシェーダーが見つからないまたはパイプライン作成に失敗した場合にエラーをスローします。
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

    /// 両方の入力パスを実行し、ブレンドモードを使用して出力をマージします。
    ///
    /// - Parameters:
    ///   - commandBuffer: 処理をエンコードする Metal コマンドバッファ。
    ///   - time: 経過時間（秒）。
    ///   - renderer: 共有リソースを提供する `MetaphorRenderer` 参照。
    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        // 入力パスを実行
        passA.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)
        passB.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)

        guard let texA = passA.output, let texB = passB.output else { return }

        // 出力テクスチャを2つの入力の大きい方に合わせる
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

    /// 必要なサイズの出力テクスチャが存在することを保証し、必要に応じて再作成します。
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
