import MetaphorCore
import simd

/// Render a scene graph tree using a ``Canvas3D`` instance.
///
/// ``SceneRenderer`` performs a depth-first traversal of the node hierarchy,
/// applying each node's local transform via push/pop matrix and drawing any
/// attached mesh or invoking custom draw callbacks.
///
/// When ``frustumPlanes`` is set, nodes with a ``Node/bounds`` are culled if
/// they fall entirely outside the frustum, avoiding unnecessary draw calls.
@MainActor
public final class SceneRenderer {
    /// The frustum planes for culling (6 planes: left, right, bottom, top, near, far).
    ///
    /// Each plane is `(nx, ny, nz, d)` where the positive half-space is visible.
    /// Set to `nil` to disable frustum culling.
    public static var frustumPlanes: [SIMD4<Float>]?

    /// Traverse the node tree depth-first and render each visible node.
    ///
    /// For each node, the renderer pushes the matrix stack, applies the node's
    /// local transform (via the quaternion-based orientation), sets the fill
    /// color if specified, draws the mesh if present, invokes the custom draw
    /// callback, recurses into children, and finally pops the matrix stack.
    ///
    /// - Parameters:
    ///   - node: The root node of the tree (or subtree) to render.
    ///   - canvas: The ``Canvas3D`` instance used for drawing.
    public static func render(node: Node, canvas: Canvas3D) {
        guard node.isVisible else { return }

        // Frustum culling
        if let planes = frustumPlanes, let bounds = node.worldBounds {
            guard bounds.intersects(frustum: planes) else { return }
        }

        canvas.pushMatrix()

        // Apply node's local transform via the 4x4 matrix
        canvas.applyMatrix(node.localTransform)

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

    /// Extract 6 frustum planes from a view-projection matrix.
    ///
    /// Uses the Gribb/Hartmann method. Each returned plane is normalized.
    ///
    /// - Parameter viewProjection: The combined view × projection matrix.
    /// - Returns: An array of 6 frustum planes (left, right, bottom, top, near, far).
    public static func extractFrustumPlanes(from viewProjection: float4x4) -> [SIMD4<Float>] {
        let m = viewProjection
        let r0 = SIMD4<Float>(m[0][0], m[1][0], m[2][0], m[3][0])
        let r1 = SIMD4<Float>(m[0][1], m[1][1], m[2][1], m[3][1])
        let r2 = SIMD4<Float>(m[0][2], m[1][2], m[2][2], m[3][2])
        let r3 = SIMD4<Float>(m[0][3], m[1][3], m[2][3], m[3][3])

        var planes: [SIMD4<Float>] = [
            r3 + r0,  // left
            r3 - r0,  // right
            r3 + r1,  // bottom
            r3 - r1,  // top
            r3 + r2,  // near
            r3 - r2,  // far
        ]

        // Normalize
        for i in 0..<planes.count {
            let n = length(SIMD3<Float>(planes[i].x, planes[i].y, planes[i].z))
            if n > 0 { planes[i] /= n }
        }

        return planes
    }
}
