@preconcurrency import Metal

/// レンダーグラフ: マルチパスレンダリングのルートノードを管理する
///
/// RenderGraph はノードのツリーを実行し、最終出力テクスチャを返す。
/// SourcePass, EffectPass, MergePass を組み合わせて複雑な合成パイプラインを構築できる。
///
/// ```swift
/// // 2つのシーンを描画してブルーム + 合成
/// let scene1 = try SourcePass(label: "bg", device: device, width: 1920, height: 1080)
/// let scene2 = try SourcePass(label: "fg", device: device, width: 1920, height: 1080)
/// let bloomed = try EffectPass(scene2, effects: [.bloom()], device: device, shaderLibrary: shaderLibrary)
/// let merged = try MergePass(scene1, bloomed, blend: .add, device: device, shaderLibrary: shaderLibrary)
/// let graph = RenderGraph(root: merged)
///
/// renderer.renderGraph = graph
/// ```
@MainActor
public final class RenderGraph {
    /// ルートノード（グラフの最終出力を提供するノード）
    public let root: RenderPassNode

    /// 初期化
    /// - Parameter root: グラフのルートノード
    public init(root: RenderPassNode) {
        self.root = root
    }

    /// グラフ全体を実行し、最終出力テクスチャを返す
    /// - Parameters:
    ///   - commandBuffer: コマンドバッファ
    ///   - time: 経過時間（秒）
    ///   - renderer: MetaphorRenderer への参照
    /// - Returns: 最終出力テクスチャ（失敗時は nil）
    @discardableResult
    public func execute(
        commandBuffer: MTLCommandBuffer,
        time: Double,
        renderer: MetaphorRenderer
    ) -> MTLTexture? {
        root.execute(commandBuffer: commandBuffer, time: time, renderer: renderer)
        return root.output
    }
}
