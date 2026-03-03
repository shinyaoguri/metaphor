import simd

/// Manage a 2D physics world using Verlet integration.
///
/// ``Physics2D`` provides a simple rigid-body simulation supporting circles and
/// axis-aligned rectangles. Bodies are integrated with Verlet integration,
/// collisions are detected via spatial hashing, and constraints are solved
/// iteratively each step.
///
/// ```swift
/// let world = Physics2D(cellSize: 50)
/// world.addGravity(0, 980)
/// let ball = world.addCircle(x: 100, y: 100, radius: 20)
/// world.step(1.0 / 60.0)
/// ```
@MainActor
public final class Physics2D {
    /// The list of physics bodies currently in the world.
    public private(set) var bodies: [PhysicsBody2D] = []

    /// The list of constraints currently in the world.
    public private(set) var constraints: [PhysicsConstraint2D] = []

    /// The global gravity acceleration applied to all non-static bodies each step.
    private var gravity: SIMD2<Float> = SIMD2(0, 0)

    /// The spatial hash used for broad-phase collision detection.
    private let spatialHash: SpatialHash2D

    /// The optional bounding box that confines all bodies within its limits.
    ///
    /// When set, bodies are clamped to stay within `min` and `max` each iteration.
    public var bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?

    /// Create a new 2D physics world.
    ///
    /// - Parameter cellSize: The cell size for the spatial hash used in broad-phase
    ///   collision detection. Larger values reduce hash overhead but increase the
    ///   number of candidate pairs checked.
    public init(cellSize: Float = 50) {
        self.spatialHash = SpatialHash2D(cellSize: cellSize)
    }

    // MARK: - Body Creation

    /// Add a circle-shaped physics body to the world.
    ///
    /// - Parameters:
    ///   - x: The initial x-coordinate of the body.
    ///   - y: The initial y-coordinate of the body.
    ///   - radius: The radius of the circle.
    ///   - mass: The mass of the body (defaults to 1.0).
    /// - Returns: The newly created ``PhysicsBody2D`` instance.
    @discardableResult
    public func addCircle(x: Float, y: Float, radius: Float, mass: Float = 1.0) -> PhysicsBody2D {
        let body = PhysicsBody2D(x: x, y: y, shape: .circle(radius: radius), mass: mass)
        bodies.append(body)
        return body
    }

    /// Add a rectangle-shaped physics body to the world.
    ///
    /// - Parameters:
    ///   - x: The initial x-coordinate of the body center.
    ///   - y: The initial y-coordinate of the body center.
    ///   - width: The width of the rectangle.
    ///   - height: The height of the rectangle.
    ///   - mass: The mass of the body (defaults to 1.0).
    /// - Returns: The newly created ``PhysicsBody2D`` instance.
    @discardableResult
    public func addRect(x: Float, y: Float, width: Float, height: Float, mass: Float = 1.0) -> PhysicsBody2D {
        let body = PhysicsBody2D(x: x, y: y, shape: .rect(width: width, height: height), mass: mass)
        bodies.append(body)
        return body
    }

    // MARK: - Forces

    /// Set the global gravity acceleration applied to all bodies each step.
    ///
    /// - Parameters:
    ///   - x: The horizontal component of the gravity vector.
    ///   - y: The vertical component of the gravity vector.
    public func addGravity(_ x: Float, _ y: Float) {
        gravity = SIMD2(x, y)
    }

    // MARK: - Constraints

    /// Add a distance constraint between two bodies.
    ///
    /// - Parameters:
    ///   - a: The first body.
    ///   - b: The second body.
    ///   - distance: The target distance between the two bodies. If `nil`, the
    ///     current distance at creation time is used.
    /// - Returns: The newly created ``PhysicsConstraint2D`` instance.
    @discardableResult
    public func addConstraint(_ a: PhysicsBody2D, _ b: PhysicsBody2D, distance: Float? = nil) -> PhysicsConstraint2D {
        let c = PhysicsConstraint2D(a, b, distance: distance)
        constraints.append(c)
        return c
    }

    /// Pin a body to a fixed world-space position.
    ///
    /// - Parameters:
    ///   - body: The body to pin.
    ///   - x: The x-coordinate of the pin position.
    ///   - y: The y-coordinate of the pin position.
    /// - Returns: The newly created pin ``PhysicsConstraint2D`` instance.
    @discardableResult
    public func pin(_ body: PhysicsBody2D, x: Float, y: Float) -> PhysicsConstraint2D {
        let c = PhysicsConstraint2D(pin: body, x: x, y: y)
        constraints.append(c)
        return c
    }

    // MARK: - Simulation

    /// Advance the simulation by one time step.
    ///
    /// This applies gravity, integrates positions using Verlet integration,
    /// then iteratively solves constraints and resolves collisions.
    ///
    /// - Parameters:
    ///   - dt: The time step in seconds.
    ///   - iterations: The number of constraint/collision solving iterations
    ///     (defaults to 4). More iterations yield more stable results.
    public func step(_ dt: Float, iterations: Int = 4) {
        // Apply gravity
        for body in bodies {
            body.applyForce(gravity * body.mass)
        }

        // Integrate
        for body in bodies {
            body.integrate(dt: dt)
        }

        // Solve constraints and collisions
        for _ in 0..<iterations {
            // Constraints
            for c in constraints {
                c.solve()
            }

            // Collision detection + resolution
            resolveCollisions()

            // Bounds
            if let bounds = bounds {
                applyBounds(bounds)
            }
        }
    }

    // MARK: - Remove

    /// Remove a body from the world along with any constraints referencing it.
    ///
    /// - Parameter body: The body to remove.
    public func removeBody(_ body: PhysicsBody2D) {
        bodies.removeAll { $0 === body }
        constraints.removeAll { $0.bodyA === body || $0.bodyB === body }
    }

    /// Remove a specific constraint from the world.
    ///
    /// - Parameter constraint: The constraint to remove.
    public func removeConstraint(_ constraint: PhysicsConstraint2D) {
        constraints.removeAll { $0 === constraint }
    }

    /// Remove all bodies and constraints from the world.
    public func clear() {
        bodies.removeAll()
        constraints.removeAll()
    }

    // MARK: - Private

    /// Detect and resolve collisions using spatial hashing for the broad phase.
    private func resolveCollisions() {
        spatialHash.clear()

        for (i, body) in bodies.enumerated() {
            let radius = boundingRadius(body)
            spatialHash.insert(index: i, position: body.position, radius: radius)
        }

        let pairs = spatialHash.queryPairs()
        for (i, j) in pairs {
            resolveCollision(bodies[i], bodies[j])
        }
    }

    /// Compute the bounding radius for broad-phase insertion.
    private func boundingRadius(_ body: PhysicsBody2D) -> Float {
        switch body.shape {
        case .circle(let r): return r
        case .rect(let w, let h): return sqrt(w * w + h * h) * 0.5
        }
    }

    /// Dispatch collision resolution based on the shape pair.
    private func resolveCollision(_ a: PhysicsBody2D, _ b: PhysicsBody2D) {
        if a.isStatic && b.isStatic { return }

        switch (a.shape, b.shape) {
        case (.circle(let ra), .circle(let rb)):
            resolveCircleCircle(a, ra, b, rb)
        case (.circle(let r), .rect(let w, let h)):
            resolveCircleRect(a, r, b, w, h)
        case (.rect(let w, let h), .circle(let r)):
            resolveCircleRect(b, r, a, w, h)
        case (.rect(let wa, let ha), .rect(let wb, let hb)):
            resolveRectRect(a, wa, ha, b, wb, hb)
        }
    }

    /// Resolve overlap between two circles using mass-weighted position correction.
    private func resolveCircleCircle(_ a: PhysicsBody2D, _ ra: Float, _ b: PhysicsBody2D, _ rb: Float) {
        let delta = b.position - a.position
        let dist = simd_length(delta)
        let minDist = ra + rb

        guard dist < minDist, dist > 0.0001 else { return }

        let normal = delta / dist
        let overlap = minDist - dist

        let totalMass = (a.isStatic ? 0 : a.mass) + (b.isStatic ? 0 : b.mass)
        guard totalMass > 0 else { return }

        if !a.isStatic { a.position -= normal * overlap * (b.isStatic ? 1 : b.mass / totalMass) }
        if !b.isStatic { b.position += normal * overlap * (a.isStatic ? 1 : a.mass / totalMass) }
    }

    /// Resolve overlap between a circle and a rectangle using closest-point projection.
    private func resolveCircleRect(_ circle: PhysicsBody2D, _ r: Float, _ rect: PhysicsBody2D, _ w: Float, _ h: Float) {
        let hw = w * 0.5
        let hh = h * 0.5
        let delta = circle.position - rect.position
        let closest = SIMD2(
            max(-hw, min(hw, delta.x)),
            max(-hh, min(hh, delta.y))
        )
        let diff = delta - closest
        let dist = simd_length(diff)

        guard dist < r, dist > 0.0001 else { return }

        let normal = diff / dist
        let overlap = r - dist

        let totalMass = (circle.isStatic ? 0 : circle.mass) + (rect.isStatic ? 0 : rect.mass)
        guard totalMass > 0 else { return }

        if !circle.isStatic { circle.position += normal * overlap * (rect.isStatic ? 1 : rect.mass / totalMass) }
        if !rect.isStatic { rect.position -= normal * overlap * (circle.isStatic ? 1 : circle.mass / totalMass) }
    }

    /// Resolve overlap between two axis-aligned rectangles using minimum penetration axis.
    private func resolveRectRect(_ a: PhysicsBody2D, _ wa: Float, _ ha: Float, _ b: PhysicsBody2D, _ wb: Float, _ hb: Float) {
        // AABB collision
        let hwa = wa * 0.5
        let hha = ha * 0.5
        let hwb = wb * 0.5
        let hhb = hb * 0.5

        let dx = b.position.x - a.position.x
        let dy = b.position.y - a.position.y
        let overlapX = hwa + hwb - abs(dx)
        let overlapY = hha + hhb - abs(dy)

        guard overlapX > 0, overlapY > 0 else { return }

        let totalMass = (a.isStatic ? 0 : a.mass) + (b.isStatic ? 0 : b.mass)
        guard totalMass > 0 else { return }

        if overlapX < overlapY {
            let sign: Float = dx > 0 ? 1 : -1
            if !a.isStatic { a.position.x -= sign * overlapX * (b.isStatic ? 1 : b.mass / totalMass) }
            if !b.isStatic { b.position.x += sign * overlapX * (a.isStatic ? 1 : a.mass / totalMass) }
        } else {
            let sign: Float = dy > 0 ? 1 : -1
            if !a.isStatic { a.position.y -= sign * overlapY * (b.isStatic ? 1 : b.mass / totalMass) }
            if !b.isStatic { b.position.y += sign * overlapY * (a.isStatic ? 1 : a.mass / totalMass) }
        }
    }

    /// Clamp all non-static bodies within the world bounds, accounting for shape size.
    private func applyBounds(_ bounds: (min: SIMD2<Float>, max: SIMD2<Float>)) {
        for body in bodies where !body.isStatic {
            switch body.shape {
            case .circle(let r):
                body.position.x = max(bounds.min.x + r, min(bounds.max.x - r, body.position.x))
                body.position.y = max(bounds.min.y + r, min(bounds.max.y - r, body.position.y))
            case .rect(let w, let h):
                let hw = w * 0.5
                let hh = h * 0.5
                body.position.x = max(bounds.min.x + hw, min(bounds.max.x - hw, body.position.x))
                body.position.y = max(bounds.min.y + hh, min(bounds.max.y - hh, body.position.y))
            }
        }
    }
}
