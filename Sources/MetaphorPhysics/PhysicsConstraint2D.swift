import simd

/// 2つの物理ボディ間、またはボディとワールド固定点間の拘束を表します。
///
/// ``PhysicsConstraint2D`` は2つのモードをサポートします:
/// - **距離拘束**: 2つのボディ間の目標距離を維持します。
/// - **ピン拘束**: 単一のボディをワールド空間の固定位置にアンカーします。
///
/// ``stiffness`` プロパティは各反復で拘束がどの程度強制されるかを制御し、
/// `1.0` は完全な補正を意味します。
@MainActor
public final class PhysicsConstraint2D {
    /// この拘束に関与する1つ目（または唯一）のボディ。
    public let bodyA: PhysicsBody2D

    /// 2つ目のボディ。ワールドへのピン拘束の場合は `nil`。
    public let bodyB: PhysicsBody2D?  // nil = ワールドにピン

    /// 2つのボディ間で維持する目標距離。
    public let targetDistance: Float

    /// ワールド空間のピン位置。距離拘束の場合は `nil`。
    public let pinPosition: SIMD2<Float>?

    /// 拘束の剛性。範囲は [0, 1]。
    ///
    /// `1.0` は各反復で拘束を完全に補正し、
    /// 低い値はより柔らかい、バネのような挙動を生成します。
    public var stiffness: Float = 1.0

    /// 2つのボディ間に距離拘束を作成します。
    ///
    /// - Parameters:
    ///   - a: 1つ目のボディ。
    ///   - b: 2つ目のボディ。
    ///   - distance: 目標距離。`nil` の場合、作成時の
    ///     2つのボディ間の現在距離が使用されます。
    public init(_ a: PhysicsBody2D, _ b: PhysicsBody2D, distance: Float? = nil) {
        self.bodyA = a
        self.bodyB = b
        self.targetDistance = distance ?? simd_length(a.position - b.position)
        self.pinPosition = nil
    }

    /// ボディをワールド空間の固定位置にアンカーするピン拘束を作成します。
    ///
    /// - Parameters:
    ///   - body: ピン留めするボディ。
    ///   - x: ピン位置の X 座標。
    ///   - y: ピン位置の Y 座標。
    public init(pin body: PhysicsBody2D, x: Float, y: Float) {
        self.bodyA = body
        self.bodyB = nil
        self.targetDistance = 0
        self.pinPosition = SIMD2(x, y)
    }

    /// ボディ位置を目標に向かって調整することでこの拘束を解決します。
    ///
    /// ピン拘束の場合、ボディは剛性係数に従ってピン位置に向かって移動されます。
    /// 距離拘束の場合、両方のボディが接続軸に沿って対称的に調整されます。
    func solve() {
        if let pin = pinPosition {
            // ピン拘束
            if !bodyA.isStatic {
                bodyA.position = mix(bodyA.position, pin, t: stiffness)
            }
            return
        }

        guard let b = bodyB else { return }

        let delta = b.position - bodyA.position
        let dist = simd_length(delta)
        guard dist > 0.0001 else { return }

        let diff = (dist - targetDistance) / dist
        let correction = delta * diff * 0.5 * stiffness

        if !bodyA.isStatic { bodyA.position += correction }
        if !b.isStatic { b.position -= correction }
    }
}
