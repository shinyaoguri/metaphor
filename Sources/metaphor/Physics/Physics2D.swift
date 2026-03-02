import simd

/// 2D 物理ワールド（Verlet 積分ベース）
@MainActor
public final class Physics2D {
    public private(set) var bodies: [PhysicsBody2D] = []
    public private(set) var constraints: [PhysicsConstraint2D] = []
    private var gravity: SIMD2<Float> = SIMD2(0, 0)
    private let spatialHash: SpatialHash2D

    /// 物理ワールドの境界
    public var bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?

    public init(cellSize: Float = 50) {
        self.spatialHash = SpatialHash2D(cellSize: cellSize)
    }

    // MARK: - Body Creation

    @discardableResult
    public func addCircle(x: Float, y: Float, radius: Float, mass: Float = 1.0) -> PhysicsBody2D {
        let body = PhysicsBody2D(x: x, y: y, shape: .circle(radius: radius), mass: mass)
        bodies.append(body)
        return body
    }

    @discardableResult
    public func addRect(x: Float, y: Float, width: Float, height: Float, mass: Float = 1.0) -> PhysicsBody2D {
        let body = PhysicsBody2D(x: x, y: y, shape: .rect(width: width, height: height), mass: mass)
        bodies.append(body)
        return body
    }

    // MARK: - Forces

    public func addGravity(_ x: Float, _ y: Float) {
        gravity = SIMD2(x, y)
    }

    // MARK: - Constraints

    @discardableResult
    public func addConstraint(_ a: PhysicsBody2D, _ b: PhysicsBody2D, distance: Float? = nil) -> PhysicsConstraint2D {
        let c = PhysicsConstraint2D(a, b, distance: distance)
        constraints.append(c)
        return c
    }

    @discardableResult
    public func pin(_ body: PhysicsBody2D, x: Float, y: Float) -> PhysicsConstraint2D {
        let c = PhysicsConstraint2D(pin: body, x: x, y: y)
        constraints.append(c)
        return c
    }

    // MARK: - Simulation

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

    public func removeBody(_ body: PhysicsBody2D) {
        bodies.removeAll { $0 === body }
        constraints.removeAll { $0.bodyA === body || $0.bodyB === body }
    }

    public func removeConstraint(_ constraint: PhysicsConstraint2D) {
        constraints.removeAll { $0 === constraint }
    }

    public func clear() {
        bodies.removeAll()
        constraints.removeAll()
    }

    // MARK: - Private

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

    private func boundingRadius(_ body: PhysicsBody2D) -> Float {
        switch body.shape {
        case .circle(let r): return r
        case .rect(let w, let h): return sqrt(w * w + h * h) * 0.5
        }
    }

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
