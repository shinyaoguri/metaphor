/// シーングラフをCanvas3Dで描画する
@MainActor
public final class SceneRenderer {
    /// DFS でツリーを走査し、各ノードで pushMatrix -> applyTransform -> 描画 -> 子 -> popMatrix
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
