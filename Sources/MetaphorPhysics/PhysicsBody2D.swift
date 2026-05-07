import simd

/// 2D物理ボディの衝突形状を表します。
public enum PhysicsShape2D {
    /// 指定半径の円。
    case circle(radius: Float)
    /// 指定幅・高さの軸整列矩形。
    case rect(width: Float, height: Float)
}

/// Verlet 積分でシミュレートされる単一の2D剛体を表します。
///
/// ``PhysicsBody2D`` は明示的な速度ではなく、現在と前回の位置を保持します。
/// 各ステップで暗黙の速度が2つの位置の差分として導出され、
/// 安定したシンプルな積分を実現します。
///
/// ``isStatic`` を `true` に設定すると、ボディを不動にします（壁や地面など）。
/// 静的ボディは衝突解消に参加しますが、位置は変更されません。
@MainActor
public final class PhysicsBody2D {
    private static let minimumMass: Float = 0.0001

    /// ワールド空間におけるボディの現在位置。
    public var position: SIMD2<Float>

    /// Verlet 積分で使用される前回タイムステップのボディ位置。
    public var previousPosition: SIMD2<Float>

    /// 現在のステップで蓄積された加速度。積分後にクリアされます。
    public var acceleration: SIMD2<Float> = .zero

    /// 力の適用と衝突重み付けに使用されるボディの質量。
    public var mass: Float {
        didSet { mass = Self.sanitizedMass(mass) }
    }

    /// ボディの衝突形状。
    public let shape: PhysicsShape2D

    /// ボディが静的（不動）かどうかを示します。
    ///
    /// 静的ボディは力、積分、衝突による位置変更の影響を受けませんが、
    /// 他のボディを押し返すことはできます。
    public var isStatic: Bool = false

    /// 反発係数（弾性）。範囲は [0, 1]。
    public var restitution: Float = 0.5 {
        didSet { restitution = Self.clampedUnit(restitution) }
    }

    /// 接触時に適用される摩擦係数。
    public var friction: Float = 0.1 {
        didSet { friction = Self.clampedUnit(friction) }
    }

    /// 指定位置・形状・質量で新しい物理ボディを作成します。
    ///
    /// - Parameters:
    ///   - x: 初期 X 座標。
    ///   - y: 初期 Y 座標。
    ///   - shape: ボディの衝突形状。
    ///   - mass: ボディの質量（デフォルトは1.0）。
    public init(x: Float, y: Float, shape: PhysicsShape2D, mass: Float = 1.0) {
        self.position = SIMD2(x, y)
        self.previousPosition = SIMD2(x, y)
        self.mass = Self.sanitizedMass(mass)
        self.shape = Self.sanitizedShape(shape)
    }

    /// Verlet 積分を実行: newPos = pos + (pos - prevPos) + acc * dt^2。
    ///
    /// 積分後、蓄積された加速度はゼロにリセットされます。
    ///
    /// - Parameter dt: タイムステップ（秒）。
    func integrate(dt: Float) {
        guard !isStatic else { return }
        let velocity = position - previousPosition
        previousPosition = position
        position = position + velocity + acceleration * (dt * dt)
        acceleration = .zero
    }

    /// ボディに力を適用し、F/m で加速度に変換します。
    ///
    /// 力は蓄積され、次の積分ステップで消費されます。
    /// 静的ボディには効果がありません。
    ///
    /// - Parameter force: 適用する力ベクトル。
    public func applyForce(_ force: SIMD2<Float>) {
        guard !isStatic else { return }
        guard mass.isFinite, mass > 0 else { return }
        acceleration += force / mass
    }

    /// Verlet 位置差分から導出されるボディの現在速度。
    public var velocity: SIMD2<Float> {
        position - previousPosition
    }

    private static func sanitizedMass(_ value: Float) -> Float {
        guard value.isFinite, value > minimumMass else { return minimumMass }
        return value
    }

    private static func sanitizedShape(_ shape: PhysicsShape2D) -> PhysicsShape2D {
        switch shape {
        case .circle(let radius):
            return .circle(radius: max(minimumMass, abs(radius)))
        case .rect(let width, let height):
            return .rect(width: max(minimumMass, abs(width)), height: max(minimumMass, abs(height)))
        }
    }

    private static func clampedUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0, min(1, value))
    }
}
