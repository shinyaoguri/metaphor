import simd

/// Represents a constraint between two physics bodies, or between a body
/// and a fixed point in the world.
///
/// ``PhysicsConstraint2D`` supports two modes:
/// - **Distance constraint**: Maintains a target distance between two bodies.
/// - **Pin constraint**: Anchors a single body to a fixed position in world space.
///
/// The ``stiffness`` property controls how strongly the constraint is
/// enforced each iteration, with `1.0` meaning full correction.
@MainActor
public final class PhysicsConstraint2D {
    /// The first (or only) body involved in this constraint.
    public let bodyA: PhysicsBody2D

    /// The second body. `nil` for a pin constraint to the world.
    public let bodyB: PhysicsBody2D?  // nil = ワールドにピン

    /// The target distance to maintain between the two bodies.
    public let targetDistance: Float

    /// The pin position in world space. `nil` for a distance constraint.
    public let pinPosition: SIMD2<Float>?

    /// The constraint's stiffness. Range is [0, 1].
    ///
    /// `1.0` fully corrects the constraint each iteration; lower values
    /// produce softer, spring-like behavior. Out-of-range values are
    /// clamped (values above 1 or negative would diverge the simulation —
    /// the same convention as `PhysicsBody2D`'s restitution/friction).
    public var stiffness: Float = 1.0 {
        didSet {
            if !stiffness.isFinite {
                stiffness = 1.0
            } else {
                stiffness = min(max(stiffness, 0), 1)
            }
        }
    }

    /// Creates a distance constraint between two bodies.
    ///
    /// - Parameters:
    ///   - a: The first body.
    ///   - b: The second body.
    ///   - distance: The target distance. If `nil`, the current distance
    ///     between the two bodies at creation time is used.
    public init(_ a: PhysicsBody2D, _ b: PhysicsBody2D, distance: Float? = nil) {
        self.bodyA = a
        self.bodyB = b
        self.targetDistance = distance ?? simd_length(a.position - b.position)
        self.pinPosition = nil
    }

    /// Creates a pin constraint that anchors a body to a fixed position in world space.
    ///
    /// - Parameters:
    ///   - body: The body to pin.
    ///   - x: The X coordinate of the pin position.
    ///   - y: The Y coordinate of the pin position.
    public init(pin body: PhysicsBody2D, x: Float, y: Float) {
        self.bodyA = body
        self.bodyB = nil
        self.targetDistance = 0
        self.pinPosition = SIMD2(x, y)
    }

    /// Solves this constraint by adjusting body positions toward the target.
    ///
    /// For a pin constraint, the body is moved toward the pin position
    /// according to the stiffness factor. For a distance constraint, both
    /// bodies are adjusted symmetrically along the connecting axis.
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
