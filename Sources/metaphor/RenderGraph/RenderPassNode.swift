import Metal

/// レンダーパスノードプロトコル
///
/// RenderGraph の各ノードが準拠するプロトコル。
/// ノードは execute() で描画を行い、結果を output テクスチャに書き出す。
@MainActor
public protocol RenderPassNode: AnyObject {
    /// ノードのラベル（デバッグ用）
    var label: String { get }

    /// 実行後の出力テクスチャ
    var output: MTLTexture? { get }

    /// ノードを実行して出力テクスチャを生成する
    /// - Parameters:
    ///   - commandBuffer: コマンドバッファ
    ///   - time: 経過時間（秒）
    ///   - renderer: MetaphorRenderer への参照
    func execute(commandBuffer: MTLCommandBuffer, time: Double, renderer: MetaphorRenderer)
}
