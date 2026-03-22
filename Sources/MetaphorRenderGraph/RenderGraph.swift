@preconcurrency import Metal
import MetaphorCore

/// マルチパスレンダリングのためのレンダーパスの有向非巡回グラフを管理します。
///
/// ``RenderGraph`` は ``RenderPassNode`` インスタンスのツリーを実行し、
/// 最終的な出力テクスチャを返します。``SourcePass``、``EffectPass``、
/// ``MergePass`` ノードを組み合わせて複雑なコンポジティングパイプラインを構築します。
///
/// ```swift
/// // 2つのシーンを描画し、一方にブルームを適用してから合成
/// let scene1 = try SourcePass(label: "bg", device: device, width: 1920, height: 1080)
/// let scene2 = try SourcePass(label: "fg", device: device, width: 1920, height: 1080)
/// let bloomed = try EffectPass(scene2, effects: [.bloom()], device: device, shaderLibrary: shaderLibrary)
/// let merged = try MergePass(scene1, bloomed, blend: .add, device: device, shaderLibrary: shaderLibrary)
/// let graph = RenderGraph(root: merged)
///
/// renderer.renderGraph = graph
/// ```
@MainActor
public final class RenderGraph: RenderGraphExecutable {
    /// 最終出力テクスチャを提供するグラフのルートノード。
    public let root: RenderPassNode

    /// 指定ルートノードで新しいレンダーグラフを作成します。
    ///
    /// - Parameter root: グラフの最終出力を生成するルートノード。
    public init(root: RenderPassNode) {
        self.root = root
    }

    /// グラフ全体を実行し、最終出力テクスチャを返します。
    ///
    /// ルートからすべてのノードを再帰的に実行し、
    /// 提供されたコマンドバッファにレンダリング処理をエンコードします。
    ///
    /// - Parameters:
    ///   - commandBuffer: レンダリング処理をエンコードする Metal コマンドバッファ。
    ///   - time: 各ノードに渡される経過時間（秒）。
    ///   - renderer: 共有リソースを提供する ``MetaphorRenderer`` 参照。
    /// - Returns: 最終出力テクスチャ。実行失敗時は `nil`。
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
