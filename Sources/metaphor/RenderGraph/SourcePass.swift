@preconcurrency import Metal

/// ソースパス: ユーザーがオフスクリーンテクスチャに描画するノード
///
/// 独自の TextureManager を持ち、onDraw クロージャでユーザーの描画コードを実行する。
/// ```swift
/// let pass = try SourcePass(label: "scene", device: device, width: 1920, height: 1080)
/// pass.onDraw = { encoder, time in
///     // Metal rendering code
/// }
/// ```
@MainActor
public final class SourcePass: RenderPassNode {
    // MARK: - Public Properties

    public let label: String

    /// 出力テクスチャ（TextureManager のカラーテクスチャ）
    public var output: MTLTexture? { textureManager.colorTexture }

    /// 描画コールバック
    /// - Parameters:
    ///   - encoder: レンダーコマンドエンコーダ
    ///   - time: 経過時間（秒）
    public var onDraw: ((MTLRenderCommandEncoder, Double) -> Void)?

    // MARK: - Private Properties

    /// オフスクリーンテクスチャマネージャ
    let textureManager: TextureManager

    // MARK: - Initialization

    /// 初期化
    /// - Parameters:
    ///   - label: ノードのラベル
    ///   - device: MTLDevice
    ///   - width: テクスチャの幅
    ///   - height: テクスチャの高さ
    ///   - sampleCount: MSAAサンプル数（デフォルト: 1、ポストプロセス互換のため）
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

    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: textureManager.renderPassDescriptor
        ) else { return }
        encoder.label = "SourcePass:\(label)"
        onDraw?(encoder, time)
        encoder.endEncoding()
    }
}
