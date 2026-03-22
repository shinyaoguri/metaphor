@preconcurrency import Metal
import MetaphorCore

/// ユーザーコードがコンテンツを描画するオフスクリーンレンダーターゲットを提供します。
///
/// ``SourcePass`` は専用の `TextureManager` を保持し、
/// ユーザーのレンダリングコードが実行される ``onDraw`` コールバックを公開します。
/// 結果のカラーテクスチャがノードの出力になります。
///
/// ```swift
/// let pass = try SourcePass(label: "scene", device: device, width: 1920, height: 1080)
/// pass.onDraw = { encoder, time in
///     // Metal レンダリングコード
/// }
/// ```
@MainActor
public final class SourcePass: RenderPassNode {
    // MARK: - パブリックプロパティ

    /// このソースパスを識別するデバッグラベル。
    public let label: String

    /// このパスで生成される出力カラーテクスチャ。
    public var output: MTLTexture? { textureManager.colorTexture }

    /// 実行時に呼び出される描画コールバック。
    ///
    /// - Parameters:
    ///   - encoder: オフスクリーンレンダーターゲット用のレンダーコマンドエンコーダー。
    ///   - time: 経過時間（秒）。
    public var onDraw: ((MTLRenderCommandEncoder, Double) -> Void)?

    // MARK: - プライベートプロパティ

    /// レンダーターゲットを提供するオフスクリーンテクスチャマネージャー。
    let textureManager: TextureManager

    // MARK: - 初期化

    /// 専用オフスクリーンレンダーターゲットで新しいソースパスを作成します。
    ///
    /// - Parameters:
    ///   - label: このパスのデバッグラベル。
    ///   - device: テクスチャ作成に使用する Metal デバイス。
    ///   - width: オフスクリーンテクスチャの幅（ピクセル単位）。
    ///   - height: オフスクリーンテクスチャの高さ（ピクセル単位）。
    ///   - sampleCount: MSAA サンプル数（ポストプロセス互換のためデフォルトは1）。
    /// - Throws: テクスチャ作成に失敗した場合にエラーをスローします。
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

    /// レンダーエンコーダーを作成し、描画コールバックを呼び出してソースパスを実行します。
    ///
    /// - Parameters:
    ///   - commandBuffer: 処理をエンコードする Metal コマンドバッファ。
    ///   - time: 経過時間（秒）。
    ///   - renderer: `MetaphorRenderer` 参照（ソースパスでは未使用）。
    public func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: textureManager.renderPassDescriptor
        ) else { return }
        encoder.label = "SourcePass:\(label)"
        onDraw?(encoder, time)
        encoder.endEncoding()
    }
}
