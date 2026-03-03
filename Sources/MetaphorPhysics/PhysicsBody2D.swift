import simd

/// Represent the collision shape of a 2D physics body.
public enum PhysicsShape2D {
    /// A circle with the given radius.
    case circle(radius: Float)
    /// An axis-aligned rectangle with the given width and height.
    case rect(width: Float, height: Float)
}

/// Represent a single 2D rigid body simulated with Verlet integration.
///
/// ``PhysicsBody2D`` stores the current and previous positions rather than an
/// explicit velocity. Each step, the implicit velocity is derived as the
/// difference between the two, providing stable and simple integration.
///
/// Set ``isStatic`` to `true` to make the body immovable (e.g. for walls or
/// ground planes). Static bodies participate in collision resolution but are
/// never displaced.
@MainActor
public final class PhysicsBody2D {
    /// The current position of the body in world space.
    public var position: SIMD2<Float>

    /// The position of the body at the previous time step, used by Verlet integration.
    public var previousPosition: SIMD2<Float>

    /// The accumulated acceleration for the current step, cleared after integration.
    public var acceleration: SIMD2<Float> = .zero

    /// The mass of the body, used for force application and collision weighting.
    public var mass: Float

    /// The collision shape of the body.
    public let shape: PhysicsShape2D

    /// Indicate whether the body is static (immovable).
    ///
    /// Static bodies are not affected by forces, integration, or collision
    /// displacement, but they still push other bodies away.
    public var isStatic: Bool = false

    /// The coefficient of restitution (bounciness) in the range [0, 1].
    public var restitution: Float = 0.5

    /// The friction coefficient applied during contact.
    public var friction: Float = 0.1

    /// Create a new physics body at the given position with the specified shape and mass.
    ///
    /// - Parameters:
    ///   - x: The initial x-coordinate.
    ///   - y: The initial y-coordinate.
    ///   - shape: The collision shape of the body.
    ///   - mass: The mass of the body (defaults to 1.0).
    public init(x: Float, y: Float, shape: PhysicsShape2D, mass: Float = 1.0) {
        self.position = SIMD2(x, y)
        self.previousPosition = SIMD2(x, y)
        self.mass = mass
        self.shape = shape
    }

    /// Perform Verlet integration: newPos = pos + (pos - prevPos) + acc * dt^2.
    ///
    /// After integration, the accumulated acceleration is reset to zero.
    ///
    /// - Parameter dt: The time step in seconds.
    func integrate(dt: Float) {
        guard !isStatic else { return }
        let velocity = position - previousPosition
        previousPosition = position
        position = position + velocity + acceleration * (dt * dt)
        acceleration = .zero
    }

    /// Apply a force to the body, converting it to acceleration via F/m.
    ///
    /// Forces are accumulated and consumed during the next integration step.
    /// This method has no effect on static bodies.
    ///
    /// - Parameter force: The force vector to apply.
    public func applyForce(_ force: SIMD2<Float>) {
        guard !isStatic else { return }
        acceleration += force / mass
    }

    /// The current velocity of the body, derived from the Verlet position difference.
    public var velocity: SIMD2<Float> {
        position - previousPosition
    }
}
