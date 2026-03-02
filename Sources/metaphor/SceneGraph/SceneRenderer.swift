/// Render a scene graph tree using a ``Canvas3D`` instance.
///
/// ``SceneRenderer`` performs a depth-first traversal of the node hierarchy,
/// applying each node's local transform via push/pop matrix and drawing any
/// attached mesh or invoking custom draw callbacks.
@MainActor
public final class SceneRenderer {
    /// Traverse the node tree depth-first and render each visible node.
    ///
    /// For each node, the renderer pushes the matrix stack, applies the node's
    /// local transform (translate, rotate, scale), sets the fill color if
    /// specified, draws the mesh if present, invokes the custom draw callback,
    /// recurses into children, and finally pops the matrix stack.
    ///
    /// - Parameters:
    ///   - node: The root node of the tree (or subtree) to render.
    ///   - canvas: The ``Canvas3D`` instance used for drawing.
    public static func render(node: Node, canvas: Canvas3D) {
        guard node.isVisible else { return }

        canvas.pushMatrix()

        // Apply node's local transform
        canvas.translate(node.position.x, node.position.y, node.position.z)
        canvas.rotateZ(node.rotation.z)
        canvas.rotateY(node.rotation.y)
        canvas.rotateX(node.rotation.x)
        canvas.scale(node.scale.x, node.scale.y, node.scale.z)

        // Set fill color if specified
        if let color = node.fillColor {
            canvas.fill(color)
        }

        // Draw mesh if present
        if let mesh = node.mesh {
            canvas.mesh(mesh)
        }

        // Custom draw callback
        node.onDraw?()

        // Recurse into children
        for child in node.children {
            render(node: child, canvas: canvas)
        }

        canvas.popMatrix()
    }
}
