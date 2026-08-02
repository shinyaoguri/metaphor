import MetaphorCore
import simd

/// Renders a scene graph tree using a `Canvas3D` instance.
///
/// ``SceneRenderer`` performs a depth-first traversal of the node hierarchy,
/// applying each node's local transform via push/pop matrix operations, and
/// drawing any attached mesh and invoking any custom draw callback.
///
/// When frustum planes are provided, a node with ``Node/bounds`` skips its own
/// drawing if it lies entirely outside the frustum. Because ``Node/bounds`` is
/// each node's own local AABB and is not guaranteed to enclose its subtree,
/// children are not culled with it and are evaluated individually (semi-hierarchical culling).
@MainActor
public final class SceneRenderer {
    /// The frustum planes used for culling (6 planes: left, right, bottom, top, near, far).
    ///
    /// Each plane is `(nx, ny, nz, d)`, and the positive half-space is visible.
    /// Set to `nil` to disable frustum culling.
    ///
    /// - Important: Because this is static global state, it is shared when drawing
    ///   multiple scenes/cameras in a single frame. In that case, pass the planes
    ///   per call using ``render(node:canvas:frustumPlanes:)`` instead.
    public static var frustumPlanes: [SIMD4<Float>]?

    /// Traverses the node tree depth-first, rendering each visible node.
    ///
    /// Uses ``frustumPlanes`` (global) for frustum culling.
    /// When drawing multiple scenes/cameras, use
    /// ``render(node:canvas:frustumPlanes:)`` instead.
    ///
    /// - Parameters:
    ///   - node: The root node of the tree (or subtree) to render.
    ///   - canvas: The `Canvas3D` instance to draw with.
    public static func render(node: Node, canvas: Canvas3D) {
        render(node: node, canvas: canvas, frustumPlanes: frustumPlanes)
    }

    /// Traverses the node tree depth-first, rendering each visible node.
    ///
    /// For each node, the renderer pushes the matrix stack, applies the node's
    /// local transform (via its quaternion-based orientation), sets the fill
    /// color if one is specified, draws its mesh if it has one, invokes any
    /// custom draw callback, recurses into its children, and finally pops the matrix stack.
    ///
    /// - Important: Culling decisions are made using ``Node/worldTransform`` (relative
    ///   to the tree), while drawing uses the canvas's matrix stack at call time. To keep
    ///   the two consistent, when culling is enabled, call this with the root node while
    ///   the canvas transform is identity (calling it under an existing transform will make culling and drawing disagree).
    ///
    /// - Parameters:
    ///   - node: The root node of the tree (or subtree) to render.
    ///   - canvas: The `Canvas3D` instance to draw with.
    ///   - frustumPlanes: The frustum planes used for culling (6 planes). `nil` disables culling.
    public static func render(node: Node, canvas: Canvas3D, frustumPlanes: [SIMD4<Float>]?) {
        guard node.isVisible else { return }

        // フラスタムカリング: bounds はノード単体のローカル AABB であり
        // サブツリーを内包する保証がないため、外れたノードは自身の描画のみ
        // スキップし、子は個別に判定する（親の外に伸びた子を誤って消さない）
        var selfCulled = false
        if let planes = frustumPlanes, let bounds = node.worldBounds {
            selfCulled = !bounds.intersects(frustum: planes)
            if selfCulled && node.children.isEmpty { return }
        }

        canvas.pushMatrix()

        // ノードのローカルトランスフォームを 4x4 行列経由で適用
        canvas.applyMatrix(node.localTransform)

        if !selfCulled {
            // フィルカラーが指定されていれば設定
            if let color = node.fillColor {
                canvas.fill(color)
            }

            // メッシュがあれば描画
            if let mesh = node.mesh {
                canvas.mesh(mesh)
            }

            // カスタム描画コールバック
            node.onDraw?()
        }

        // 子に再帰
        for child in node.children {
            render(node: child, canvas: canvas, frustumPlanes: frustumPlanes)
        }

        canvas.popMatrix()
    }

    /// Extracts six frustum planes from a view-projection matrix.
    ///
    /// Uses the Gribb/Hartmann method. Each returned plane is normalized.
    ///
    /// - Parameter viewProjection: The combined view x projection matrix.
    ///   Assumes the Metal depth convention (clip-space z in [0, 1], the form
    ///   produced by Core's `perspectiveFov` / `orthographic`).
    /// - Returns: An array of six frustum planes (left, right, bottom, top, near, far).
    public static func extractFrustumPlanes(from viewProjection: float4x4) -> [SIMD4<Float>] {
        let m = viewProjection
        let r0 = SIMD4<Float>(m[0][0], m[1][0], m[2][0], m[3][0])
        let r1 = SIMD4<Float>(m[0][1], m[1][1], m[2][1], m[3][1])
        let r2 = SIMD4<Float>(m[0][2], m[1][2], m[2][2], m[3][2])
        let r3 = SIMD4<Float>(m[0][3], m[1][3], m[2][3], m[3][3])

        var planes: [SIMD4<Float>] = [
            r3 + r0,  // 左
            r3 - r0,  // 右
            r3 + r1,  // 下
            r3 - r1,  // 上
            r2,       // ニア（Metal 規約 z ∈ [0, 1]: クリップ条件は 0 ≤ z なので r2 単独。
                      //       OpenGL 規約 z ∈ [-1, 1] の r3 + r2 ではニア平面が手前に
                      //       ずれ、カメラ背後のオブジェクトがカリングされない）
            r3 - r2,  // ファー
        ]

        // 正規化
        for i in 0..<planes.count {
            let n = length(SIMD3<Float>(planes[i].x, planes[i].y, planes[i].z))
            if n > 0 { planes[i] /= n }
        }

        return planes
    }
}
