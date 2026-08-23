import MetaphorCore
import MetaphorSceneGraph

// MARK: - シーングラフブリッジ

extension Sketch {
    /// Creates a scene graph node.
    ///
    /// - Parameter name: An optional name for the node.
    /// - Returns: A new ``MetaphorSceneGraph/Node`` instance.
    public func createNode(_ name: String = "") -> Node {
        Node(name: name)
    }

    /// Renders a scene graph from the given root node.
    ///
    /// - Parameter root: The root node of the scene graph to render.
    public func drawScene(_ root: Node) {
        SceneRenderer.render(node: root, canvas: context.canvas3D)
    }
}
