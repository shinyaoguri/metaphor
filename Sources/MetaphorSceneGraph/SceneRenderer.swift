import MetaphorCore
import simd

/// `Canvas3D` インスタンスを使用してシーングラフツリーをレンダリングします。
///
/// ``SceneRenderer`` はノード階層の深さ優先トラバーサルを行い、
/// 各ノードのローカルトランスフォームを push/pop マトリクスで適用し、
/// アタッチされたメッシュの描画やカスタム描画コールバックの呼び出しを行います。
///
/// ``frustumPlanes`` が設定されている場合、``Node/bounds`` を持つノードが
/// フラスタムの完全に外側にある場合はカリングされ、不要な描画呼び出しを回避します。
@MainActor
public final class SceneRenderer {
    /// カリング用のフラスタム平面（6平面: 左、右、下、上、ニア、ファー）。
    ///
    /// 各平面は `(nx, ny, nz, d)` で、正の半空間が可視です。
    /// フラスタムカリングを無効にするには `nil` を設定してください。
    public static var frustumPlanes: [SIMD4<Float>]?

    /// ノードツリーを深さ優先でトラバースし、各可視ノードをレンダリングします。
    ///
    /// 各ノードに対して、レンダラーはマトリクススタックをプッシュし、
    /// ノードのローカルトランスフォーム（クォータニオンベースの向き経由）を適用し、
    /// フィルカラーが指定されていれば設定し、メッシュがあれば描画し、
    /// カスタム描画コールバックを呼び出し、子に再帰し、最後にマトリクススタックをポップします。
    ///
    /// - Parameters:
    ///   - node: レンダリングするツリー（またはサブツリー）のルートノード。
    ///   - canvas: 描画に使用する `Canvas3D` インスタンス。
    public static func render(node: Node, canvas: Canvas3D) {
        guard node.isVisible else { return }

        // フラスタムカリング
        if let planes = frustumPlanes, let bounds = node.worldBounds {
            guard bounds.intersects(frustum: planes) else { return }
        }

        canvas.pushMatrix()

        // ノードのローカルトランスフォームを 4x4 行列経由で適用
        canvas.applyMatrix(node.localTransform)

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

        // 子に再帰
        for child in node.children {
            render(node: child, canvas: canvas)
        }

        canvas.popMatrix()
    }

    /// ビュー・プロジェクション行列から6つのフラスタム平面を抽出します。
    ///
    /// Gribb/Hartmann 法を使用します。返される各平面は正規化済みです。
    ///
    /// - Parameter viewProjection: 合成されたビュー × プロジェクション行列。
    /// - Returns: 6つのフラスタム平面の配列（左、右、下、上、ニア、ファー）。
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
            r3 + r2,  // ニア
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
