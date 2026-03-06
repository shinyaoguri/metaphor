import MetaphorCore
import MetaphorSceneGraph

// MARK: - Scene Graph Bridge

extension Sketch {
    /// Create a scene graph node.
    ///
    /// - Parameter name: The optional name for the node.
    /// - Returns: A new ``Node`` instance.
    public func createNode(_ name: String = "") -> Node {
        Node(name: name)
    }

    /// Draw a scene graph starting from the specified root node.
    ///
    /// - Parameter root: The root node of the scene graph to render.
    public func drawScene(_ root: Node) {
        SceneRenderer.render(node: root, canvas: context.canvas3D)
    }
}
