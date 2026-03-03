import simd

/// Represent a constraint between two physics bodies or between a body and a fixed world point.
///
/// ``PhysicsConstraint2D`` supports two modes:
/// - **Distance constraint**: Maintain a target distance between two bodies.
/// - **Pin constraint**: Anchor a single body to a fixed world-space position.
///
/// The ``stiffness`` property controls how aggressively the constraint is
/// enforced each iteration, where `1.0` means full correction.
@MainActor
public final class PhysicsConstraint2D {
    /// The first (or only) body involved in this constraint.
    public let bodyA: PhysicsBody2D

    /// The second body, or `nil` for a pin constraint attached to the world.
    public let bodyB: PhysicsBody2D?  // nil = pin to world

    /// The target distance to maintain between the two bodies.
    public let targetDistance: Float

    /// The world-space pin position, or `nil` for a distance constraint.
    public let pinPosition: SIMD2<Float>?

    /// The stiffness of the constraint in the range [0, 1].
    ///
    /// A value of `1.0` fully corrects the constraint each iteration, while
    /// lower values produce softer, springlike behavior.
    public var stiffness: Float = 1.0

    /// Create a distance constraint between two bodies.
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

    /// Create a pin constraint that anchors a body to a fixed world-space position.
    ///
    /// - Parameters:
    ///   - body: The body to pin.
    ///   - x: The x-coordinate of the pin position.
    ///   - y: The y-coordinate of the pin position.
    public init(pin body: PhysicsBody2D, x: Float, y: Float) {
        self.bodyA = body
        self.bodyB = nil
        self.targetDistance = 0
        self.pinPosition = SIMD2(x, y)
    }

    /// Solve this constraint by adjusting body positions toward the target.
    ///
    /// For pin constraints, the body is moved toward the pin position by
    /// the stiffness factor. For distance constraints, both bodies are
    /// adjusted symmetrically along the connecting axis.
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
