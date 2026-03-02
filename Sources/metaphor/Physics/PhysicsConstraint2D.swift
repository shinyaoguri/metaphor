/// 2D 物理制約
@MainActor
public final class PhysicsConstraint2D {
    public let bodyA: PhysicsBody2D
    public let bodyB: PhysicsBody2D?  // nil = pin to world
    public let targetDistance: Float
    public let pinPosition: SIMD2<Float>?
    public var stiffness: Float = 1.0

    /// 2体間の距離制約
    public init(_ a: PhysicsBody2D, _ b: PhysicsBody2D, distance: Float? = nil) {
        self.bodyA = a
        self.bodyB = b
        self.targetDistance = distance ?? simd_length(a.position - b.position)
        self.pinPosition = nil
    }

    /// ピン制約（ワールド座標に固定）
    public init(pin body: PhysicsBody2D, x: Float, y: Float) {
        self.bodyA = body
        self.bodyB = nil
        self.targetDistance = 0
        self.pinPosition = SIMD2(x, y)
    }

    func solve() {
        if let pin = pinPosition {
            // Pin constraint
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
