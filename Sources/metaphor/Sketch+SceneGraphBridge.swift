import MetaphorCore
import MetaphorSceneGraph

// MARK: - シーングラフブリッジ

extension Sketch {
    /// シーングラフノードを作成します。
    ///
    /// - Parameter name: ノードのオプション名。
    /// - Returns: 新しい ``MetaphorSceneGraph/Node`` インスタンス。
    public func createNode(_ name: String = "") -> Node {
        Node(name: name)
    }

    /// 指定ルートノードからシーングラフを描画します。
    ///
    /// - Parameter root: レンダリングするシーングラフのルートノード。
    public func drawScene(_ root: Node) {
        SceneRenderer.render(node: root, canvas: context.canvas3D)
    }
}
