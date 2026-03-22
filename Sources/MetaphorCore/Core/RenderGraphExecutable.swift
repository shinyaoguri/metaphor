@preconcurrency import Metal

/// レンダラーが実行可能なレンダーグラフのインターフェースを定義します。
///
/// このプロトコルは MetaphorCore と MetaphorRenderGraph の間の循環依存を解消します。
/// MetaphorRenderGraph の具象 `RenderGraph` クラスがこのプロトコルに準拠し、
/// ``MetaphorRenderer`` はプロトコルのみを参照します。
@MainActor
public protocol RenderGraphExecutable: AnyObject {
    /// レンダーグラフを実行し、最終出力テクスチャを返します。
    ///
    /// - Parameters:
    ///   - commandBuffer: ワークをエンコードする Metal コマンドバッファ
    ///   - time: 経過時間（秒）
    ///   - renderer: 共有リソースを提供する ``MetaphorRenderer`` 参照
    /// - Returns: 最終出力テクスチャ。実行に失敗した場合は `nil`
    func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer) -> MTLTexture?
}
