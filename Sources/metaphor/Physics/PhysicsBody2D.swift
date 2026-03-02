import simd

/// 2D 物理ボディの形状
public enum PhysicsShape2D {
    case circle(radius: Float)
    case rect(width: Float, height: Float)
}

/// 2D 物理ボディ（Verlet 積分）
@MainActor
public final class PhysicsBody2D {
    public var position: SIMD2<Float>
    public var previousPosition: SIMD2<Float>
    public var acceleration: SIMD2<Float> = .zero
    public var mass: Float
    public let shape: PhysicsShape2D
    public var isStatic: Bool = false
    public var restitution: Float = 0.5
    public var friction: Float = 0.1

    public init(x: Float, y: Float, shape: PhysicsShape2D, mass: Float = 1.0) {
        self.position = SIMD2(x, y)
        self.previousPosition = SIMD2(x, y)
        self.mass = mass
        self.shape = shape
    }

    /// Verlet integration: newPos = pos + (pos - prevPos) + acc * dt²
    func integrate(dt: Float) {
        guard !isStatic else { return }
        let velocity = position - previousPosition
        previousPosition = position
        position = position + velocity + acceleration * (dt * dt)
        acceleration = .zero
    }

    public func applyForce(_ force: SIMD2<Float>) {
        guard !isStatic else { return }
        acceleration += force / mass
    }

    /// 現在の速度を取得
    public var velocity: SIMD2<Float> {
        position - previousPosition
    }
}
