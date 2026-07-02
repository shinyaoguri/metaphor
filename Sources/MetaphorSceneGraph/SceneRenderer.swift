import MetaphorCore
import simd

/// `Canvas3D` インスタンスを使用してシーングラフツリーをレンダリングします。
///
/// ``SceneRenderer`` はノード階層の深さ優先トラバーサルを行い、
/// 各ノードのローカルトランスフォームを push/pop マトリクスで適用し、
/// アタッチされたメッシュの描画やカスタム描画コールバックの呼び出しを行います。
///
/// フラスタム平面が与えられている場合、``Node/bounds`` を持つノードが
/// フラスタムの完全に外側にあれば自身の描画をスキップします。``Node/bounds`` は
/// ノード単体のローカル AABB でありサブツリーを内包する保証がないため、
/// 子はカリングせず個別に判定します（セミヒエラルキカルカリング）。
@MainActor
public final class SceneRenderer {
    /// カリング用のフラスタム平面（6平面: 左、右、下、上、ニア、ファー）。
    ///
    /// 各平面は `(nx, ny, nz, d)` で、正の半空間が可視です。
    /// フラスタムカリングを無効にするには `nil` を設定してください。
    ///
    /// - Important: static なグローバル状態のため、1 フレームで複数のシーン/カメラを
    ///   描く場合は共有されます。その場合は
    ///   ``render(node:canvas:frustumPlanes:)`` で呼び出しごとに平面を渡してください。
    public static var frustumPlanes: [SIMD4<Float>]?

    /// ノードツリーを深さ優先でトラバースし、各可視ノードをレンダリングします。
    ///
    /// フラスタムカリングには ``frustumPlanes``（グローバル）を使用します。
    /// 複数シーン/カメラを描く場合は ``render(node:canvas:frustumPlanes:)`` を
    /// 使ってください。
    ///
    /// - Parameters:
    ///   - node: レンダリングするツリー（またはサブツリー）のルートノード。
    ///   - canvas: 描画に使用する `Canvas3D` インスタンス。
    public static func render(node: Node, canvas: Canvas3D) {
        render(node: node, canvas: canvas, frustumPlanes: frustumPlanes)
    }

    /// ノードツリーを深さ優先でトラバースし、各可視ノードをレンダリングします。
    ///
    /// 各ノードに対して、レンダラーはマトリクススタックをプッシュし、
    /// ノードのローカルトランスフォーム（クォータニオンベースの向き経由）を適用し、
    /// フィルカラーが指定されていれば設定し、メッシュがあれば描画し、
    /// カスタム描画コールバックを呼び出し、子に再帰し、最後にマトリクススタックをポップします。
    ///
    /// - Important: カリング判定は ``Node/worldTransform``（ツリー基準）で行い、
    ///   描画は呼び出し時点の canvas 行列スタック基準で行います。両者が一致するよう、
    ///   カリングを使う場合はルートノードを canvas の変換が identity の状態で
    ///   渡してください（既存の変換の下で呼ぶと判定と描画がズレます）。
    ///
    /// - Parameters:
    ///   - node: レンダリングするツリー（またはサブツリー）のルートノード。
    ///   - canvas: 描画に使用する `Canvas3D` インスタンス。
    ///   - frustumPlanes: カリング用のフラスタム平面（6平面）。`nil` でカリング無効。
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

    /// ビュー・プロジェクション行列から6つのフラスタム平面を抽出します。
    ///
    /// Gribb/Hartmann 法を使用します。返される各平面は正規化済みです。
    ///
    /// - Parameter viewProjection: 合成されたビュー × プロジェクション行列。
    ///   Metal 深度規約（クリップ空間 z ∈ [0, 1]。Core の `perspectiveFov` /
    ///   `orthographic` が生成する形式）を前提とします。
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
