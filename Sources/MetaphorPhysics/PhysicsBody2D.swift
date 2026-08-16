import simd

/// Represents the collision shape of a 2D physics body.
public enum PhysicsShape2D {
    /// A circle with the given radius.
    case circle(radius: Float)
    /// An axis-aligned rectangle with the given width and height.
    case rect(width: Float, height: Float)
}

/// Represents a single 2D rigid body simulated with Verlet integration.
///
/// ``PhysicsBody2D`` holds the current and previous position instead of an
/// explicit velocity. An implicit velocity is derived each step as the
/// difference between the two positions, giving stable, simple integration.
///
/// Setting ``isStatic`` to `true` makes the body immovable (e.g. walls or
/// ground). Static bodies participate in collision resolution but their
/// position never changes.
@MainActor
public final class PhysicsBody2D {
    private static let minimumMass: Float = 0.0001

    /// The body's current position in world space.
    public var position: SIMD2<Float>

    /// The body's position at the previous time step, used by Verlet integration.
    public var previousPosition: SIMD2<Float>

    /// The acceleration accumulated for the current step. Cleared after integration.
    public var acceleration: SIMD2<Float> = .zero

    /// The body's mass, used for force application and collision weighting.
    public var mass: Float {
        didSet { mass = Self.sanitizedMass(mass) }
    }

    /// The body's collision shape.
    public let shape: PhysicsShape2D

    /// Indicates whether the body is static (immovable).
    ///
    /// Static bodies are unaffected by position changes from forces,
    /// integration, or collisions, but can still push other bodies back.
    public var isStatic: Bool = false

    /// The coefficient of restitution (bounciness). Range is [0, 1].
    ///
    /// The smaller value of the two touching bodies is used. Contacts slower
    /// than the approach speed gravity adds in a single step are treated as
    /// perfectly inelastic, so resting bodies settle instead of jittering.
    /// World ``Physics2D/bounds`` are unaffected — see their documentation.
    public var restitution: Float = 0.5 {
        didSet { restitution = Self.clampedUnit(restitution) }
    }

    /// The friction coefficient applied on contact.
    ///
    /// The average of the two touching bodies is used, and it bounds the
    /// tangential impulse as a fraction of the normal impulse (Coulomb):
    /// `0` slides freely, `1` sheds the tangential motion of the contact.
    public var friction: Float = 0.1 {
        didSet { friction = Self.clampedUnit(friction) }
    }

    /// Creates a new physics body with the given position, shape, and mass.
    ///
    /// - Parameters:
    ///   - x: The initial X coordinate.
    ///   - y: The initial Y coordinate.
    ///   - shape: The body's collision shape.
    ///   - mass: The body's mass (defaults to 1.0).
    public init(x: Float, y: Float, shape: PhysicsShape2D, mass: Float = 1.0) {
        self.position = SIMD2(x, y)
        self.previousPosition = SIMD2(x, y)
        self.mass = Self.sanitizedMass(mass)
        self.shape = Self.sanitizedShape(shape)
    }

    /// Performs Verlet integration: newPos = pos + (pos - prevPos) + acc * dt^2.
    ///
    /// After integration, the accumulated acceleration is reset to zero.
    ///
    /// - Parameter dt: The time step (seconds).
    func integrate(dt: Float) {
        guard !isStatic else { return }
        let velocity = position - previousPosition
        previousPosition = position
        position = position + velocity + acceleration * (dt * dt)
        acceleration = .zero
    }

    /// Applies a force to the body, converting it to acceleration via F/m.
    ///
    /// Forces accumulate and are consumed on the next integration step.
    /// Has no effect on static bodies.
    ///
    /// - Parameter force: The force vector to apply.
    public func applyForce(_ force: SIMD2<Float>) {
        guard !isStatic else { return }
        guard mass.isFinite, mass > 0 else { return }
        acceleration += force / mass
    }

    /// The body's current velocity, derived from the Verlet position difference.
    ///
    /// The unit is displacement **per step**, not per second: a body moving
    /// `8` covers 8 units in every ``Physics2D/step(_:iterations:)`` call.
    /// Give a body an initial velocity by offsetting ``previousPosition``
    /// (`previousPosition = position - velocity`); there is no setter.
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
