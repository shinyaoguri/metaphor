import Metal
import MetaphorCore
import simd

/// フラスタムカリング用の軸整列バウンディングボックス。
public struct AABB: Sendable {
    /// バウンディングボックスの最小コーナー。
    public var min: SIMD3<Float>

    /// バウンディングボックスの最大コーナー。
    public var max: SIMD3<Float>

    /// 指定した最小・最大コーナーで AABB を作成します。
    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    /// バウンディングボックスの中心。
    public var center: SIMD3<Float> {
        (min + max) * 0.5
    }

    /// 各軸に沿ったハーフエクステント（半分のサイズ）。
    public var extents: SIMD3<Float> {
        (max - min) * 0.5
    }

    /// この AABB が指定フラスタム平面の外側にあるかテストします。
    ///
    /// 各平面は (nx, ny, nz, d) で表され、正の半空間が可視側です。
    ///
    /// - Parameter planes: フラスタム平面の配列（通常6枚）。
    /// - Returns: AABB がフラスタム内に少なくとも部分的にある場合は `true`。
    public func intersects(frustum planes: [SIMD4<Float>]) -> Bool {
        let c = center
        let e = extents
        for plane in planes {
            let n = SIMD3<Float>(plane.x, plane.y, plane.z)
            let d = plane.w
            let r = dot(e, abs(n))
            let s = dot(c, n) + d
            if s + r < 0 { return false }
        }
        return true
    }

    /// この AABB を 4x4 行列で変換し、新しい（より大きい）AABB を生成します。
    public func transformed(by matrix: float4x4) -> AABB {
        let corners: [SIMD3<Float>] = [
            SIMD3(min.x, min.y, min.z), SIMD3(max.x, min.y, min.z),
            SIMD3(min.x, max.y, min.z), SIMD3(max.x, max.y, min.z),
            SIMD3(min.x, min.y, max.z), SIMD3(max.x, min.y, max.z),
            SIMD3(min.x, max.y, max.z), SIMD3(max.x, max.y, max.z),
        ]
        var newMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var newMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for corner in corners {
            let p = matrix * SIMD4<Float>(corner, 1.0)
            let p3 = SIMD3<Float>(p.x, p.y, p.z)
            newMin = pointwiseMin(newMin, p3)
            newMax = pointwiseMax(newMax, p3)
        }
        return AABB(min: newMin, max: newMax)
    }
}

/// 階層的なシーングラフのノードを表します。
///
/// 各 ``Node`` は ``position``、``orientation``（クォータニオン）、``scale`` で
/// 定義されるローカルトランスフォームを持ちます。トランスフォームは階層的に合成され、
/// 子の ``worldTransform`` は親のワールドトランスフォームに自身の ``localTransform`` を
/// 掛けたものになります。
///
/// ノードはオプションでレンダリング用の ``mesh`` や、カスタム描画ロジック用の
/// ``onDraw`` コールバックを保持できます。``SceneRenderer`` を使用してツリーを
/// トラバースし、`Canvas3D` でレンダリングします。
///
/// ```swift
/// let root = Node(name: "root")
/// let child = Node(name: "cube")
/// child.mesh = cubeMesh
/// child.position = SIMD3(2, 0, 0)
/// root.addChild(child)
/// SceneRenderer.render(node: root, canvas: canvas)
/// ```
@MainActor
public final class Node {
    /// このノードの名前。識別と検索に使用します。
    public var name: String

    /// 親に対するノードのローカル位置。
    public var position: SIMD3<Float> = .zero {
        didSet { invalidateTransform() }
    }

    /// クォータニオンとしてのノードのローカル向き。
    public var orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)) {
        didSet { invalidateTransform() }
    }

    /// 各軸に沿ったノードのローカルスケール。
    public var scale: SIMD3<Float> = SIMD3(1, 1, 1) {
        didSet { invalidateTransform() }
    }

    /// ノードとその子をレンダリングするかどうかを示します。
    public var isVisible: Bool = true

    /// このノードの位置に描画するオプションのメッシュ。
    public var mesh: Mesh?

    /// メッシュのレンダリング時に適用するオプションのフィルカラー。
    public var fillColor: Color?

    /// シーントラバーサル中に呼び出されるオプションのカスタム描画コールバック。
    public var onDraw: (() -> Void)?

    /// フラスタムカリング用のオプションのバウンディングボックス（ローカル空間）。
    public var bounds: AABB?

    /// 親ノード。ルートの場合は `nil`。
    public private(set) weak var parent: Node?

    /// 順序付き子ノードのリスト。
    public private(set) var children: [Node] = []

    // MARK: - トランスフォームキャッシュ

    private var _localTransformDirty: Bool = true
    private var _worldTransformDirty: Bool = true
    private var _cachedLocalTransform: float4x4 = float4x4(1)
    private var _cachedWorldTransform: float4x4 = float4x4(1)

    /// ローカルとワールドのトランスフォームをダーティとしてマークし、すべての子孫に伝播します。
    private func invalidateTransform() {
        guard _localTransformDirty == false || _worldTransformDirty == false else { return }
        _localTransformDirty = true
        invalidateWorldTransform()
    }

    /// ワールドトランスフォームのみをダーティとしてマークし、すべての子孫に伝播します。
    private func invalidateWorldTransform() {
        guard _worldTransformDirty == false else { return }
        _worldTransformDirty = true
        for child in children {
            child.invalidateWorldTransform()
        }
    }

    /// 指定名で新しいノードを作成します。
    ///
    /// - Parameter name: 識別用の名前（デフォルトは空文字列）。
    public init(name: String = "") {
        self.name = name
    }

    // MARK: - トランスフォーム

    /// オイラー角から回転を設定します（便利メソッド）。
    ///
    /// Rz * Ry * Rx として合成されます（旧オイラーベース API と同じ順序）。
    ///
    /// - Parameters:
    ///   - x: X 軸周りの回転（ラジアン）。
    ///   - y: Y 軸周りの回転（ラジアン）。
    ///   - z: Z 軸周りの回転（ラジアン）。
    public func setRotation(x: Float = 0, y: Float = 0, z: Float = 0) {
        orientation = simd_quatf(angle: z, axis: SIMD3(0, 0, 1))
                    * simd_quatf(angle: y, axis: SIMD3(0, 1, 0))
                    * simd_quatf(angle: x, axis: SIMD3(1, 0, 0))
    }

    /// 現在の向きに対してクォータニオンで相対的にノードを回転させます。
    ///
    /// - Parameter rotation: 適用する回転。
    public func rotate(by rotation: simd_quatf) {
        orientation = rotation * orientation
    }

    /// position、orientation、scale からのローカルトランスフォーム行列（キャッシュ済み）。
    ///
    /// T * R * S として合成されます。position、orientation、
    /// または scale が変更された場合のみ再計算されます。
    public var localTransform: float4x4 {
        if _localTransformDirty {
            let t = float4x4(translation: position)
            let r = float4x4(orientation)
            let s = float4x4(scale: scale)
            _cachedLocalTransform = t * r * s
            _localTransformDirty = false
        }
        return _cachedLocalTransform
    }

    /// すべての祖先トランスフォームを合成したワールドトランスフォーム（キャッシュ済み）。
    ///
    /// このノードまたは祖先のトランスフォームが変更された場合のみ再計算されます。
    public var worldTransform: float4x4 {
        if _worldTransformDirty {
            if let parent = parent {
                _cachedWorldTransform = parent.worldTransform * localTransform
            } else {
                _cachedWorldTransform = localTransform
            }
            _worldTransformDirty = false
        }
        return _cachedWorldTransform
    }

    /// ローカル bounds とワールドトランスフォームから計算されるワールド空間のバウンディングボックス。
    public var worldBounds: AABB? {
        bounds?.transformed(by: worldTransform)
    }

    // MARK: - 階層

    /// このノードに子ノードを追加します。
    ///
    /// 子が既に親を持っている場合、まずその親から削除されます。
    ///
    /// - Parameter child: 子として追加するノード。
    public func addChild(_ child: Node) {
        child.parent?.removeChild(child)
        child.parent = self
        children.append(child)
        child.invalidateWorldTransform()
    }

    /// このノードから子ノードを削除します。
    ///
    /// - Parameter child: 削除する子ノード。
    public func removeChild(_ child: Node) {
        children.removeAll { $0 === child }
        child.parent = nil
        child.invalidateWorldTransform()
    }

    /// このノードからすべての子を削除します。
    public func removeAllChildren() {
        for child in children {
            child.parent = nil
            child.invalidateWorldTransform()
        }
        children.removeAll()
    }

    /// 深さ優先探索で名前から子孫ノードを検索します。
    ///
    /// - Parameter name: 検索する名前。
    /// - Returns: 名前が一致する最初のノード。見つからない場合は `nil`。
    public func find(_ name: String) -> Node? {
        if self.name == name { return self }
        for child in children {
            if let found = child.find(name) { return found }
        }
        return nil
    }

    // MARK: - 方向ヘルパー

    /// ワールド空間での前方向ベクトル（負の Z）。
    public var forward: SIMD3<Float> {
        let q = worldOrientation
        return q.act(SIMD3(0, 0, -1))
    }

    /// ワールド空間での右方向ベクトル（正の X）。
    public var right: SIMD3<Float> {
        let q = worldOrientation
        return q.act(SIMD3(1, 0, 0))
    }

    /// ワールド空間での上方向ベクトル（正の Y）。
    public var up: SIMD3<Float> {
        let q = worldOrientation
        return q.act(SIMD3(0, 1, 0))
    }

    /// ワールド空間での向き（親 + ローカルクォータニオンの合成）。
    public var worldOrientation: simd_quatf {
        if let parent = parent {
            return parent.worldOrientation * orientation
        }
        return orientation
    }

    /// このノードを指定ワールド空間ターゲットに向けます。
    ///
    /// - Parameters:
    ///   - target: 注視するポイント。
    ///   - worldUp: ワールド上方向（デフォルトは +Y）。
    public func lookAt(_ target: SIMD3<Float>, worldUp: SIMD3<Float> = SIMD3(0, 1, 0)) {
        let worldPos = SIMD3<Float>(worldTransform.columns.3.x,
                                     worldTransform.columns.3.y,
                                     worldTransform.columns.3.z)
        let dir = normalize(target - worldPos)
        let forward = SIMD3<Float>(0, 0, -1)

        let dotVal = dot(forward, dir)
        if dotVal > 0.9999 {
            orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
            return
        }
        if dotVal < -0.9999 {
            orientation = simd_quatf(angle: .pi, axis: worldUp)
            return
        }

        let axis = normalize(cross(forward, dir))
        let angle = acos(dotVal)
        var q = simd_quatf(angle: angle, axis: axis)

        // 親の回転の寄与を除去
        if let parent = parent {
            q = parent.worldOrientation.inverse * q
        }
        orientation = q
    }
}
