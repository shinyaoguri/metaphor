import Metal
import MetaphorCore

/// ``RenderGraph`` 内のノードのインターフェースを定義します。
///
/// ``RenderPassNode`` に準拠する各ノードは
/// ``execute(commandBuffer:time:renderer:)`` メソッドでレンダリング処理を行い、
/// ``output`` テクスチャプロパティ経由で結果を公開します。
@MainActor
public protocol RenderPassNode: AnyObject {
    /// このノードを識別するデバッグラベル。
    var label: String { get }

    /// 実行後に生成される出力テクスチャ。未実行の場合は `nil`。
    var output: MTLTexture? { get }

    /// このノードのレンダリング処理を実行し、``output`` テクスチャを生成します。
    ///
    /// - Parameters:
    ///   - commandBuffer: 処理をエンコードする Metal コマンドバッファ。
    ///   - time: 経過時間（秒）。
    ///   - renderer: 共有リソースを提供する `MetaphorRenderer` 参照。
    func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer)
}
