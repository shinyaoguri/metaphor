@preconcurrency import Metal

/// マージパス: 2つのパスの出力をブレンド合成するノード
///
/// コンピュートシェーダーを使い、指定されたブレンドモードで2テクスチャを合成する。
/// ```swift
/// let merged = try MergePass(scenePass, fxPass, blend: .add, device: device, shaderLibrary: shaderLibrary)
/// ```
@MainActor
public final class MergePass: RenderPassNode {
    // MARK: - Blend Type

    /// マージ時のブレンドモード
    public enum BlendType: String, CaseIterable, Sendable {
        /// 加算合成
        case add
        /// アルファ合成（B over A）
        case alpha
        /// 乗算合成
        case multiply
        /// スクリーン合成
        case screen

        /// シェーダーに渡すブレンドモード値
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

    /// コンピュートシェーダーに渡すパラメータ
    private struct MergeParams {
        var blend_mode: UInt32
    }

    // MARK: - Public Properties

    public let label: String
    public var output: MTLTexture?

    /// ブレンドモード（実行時に変更可能）
    public var blendType: BlendType

    // MARK: - Private Properties

    private let passA: RenderPassNode
    private let passB: RenderPassNode
    private let device: MTLDevice
    private let mergePipeline: MTLComputePipelineState
    private var outputTexture: MTLTexture?
    private var outputWidth: Int = 0
    private var outputHeight: Int = 0

    // MARK: - Initialization

    /// 初期化
    /// - Parameters:
    ///   - a: ベースパス（背景レイヤー）
    ///   - b: オーバーレイパス（前景レイヤー）
    ///   - blend: ブレンドモード
    ///   - device: MTLDevice
    ///   - shaderLibrary: ShaderLibrary
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

        // マージ用コンピュートパイプラインを作成
        guard let function = shaderLibrary.function(
            named: MergeShaders.FunctionName.mergeTextures,
            from: ShaderLibrary.BuiltinKey.merge
        ) else {
            throw MergePassError.shaderNotFound(MergeShaders.FunctionName.mergeTextures)
        }
        self.mergePipeline = try PipelineFactory.buildCompute(device: device, function: function)
    }

    // MARK: - RenderPassNode

    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        // 入力パスを実行
        passA.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)
        passB.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)

        guard let texA = passA.output, let texB = passB.output else { return }

        // 出力テクスチャのサイズを大きい方に合わせる
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

    // MARK: - Private

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

enum MergePassError: Error {
    case shaderNotFound(String)
}
