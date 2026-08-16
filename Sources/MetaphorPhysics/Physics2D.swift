import simd

/// Manages a 2D physics world using Verlet integration.
///
/// ``Physics2D`` provides a simple rigid-body simulation supporting circles
/// and axis-aligned rectangles. Bodies are integrated with Verlet
/// integration, collisions are detected with a spatial hash, and constraints
/// are solved iteratively each step.
///
/// ```swift
/// let world = Physics2D(cellSize: 50)
/// world.setGravity(0, 980)
/// let ball = world.addCircle(x: 100, y: 100, radius: 20)
/// world.step(1.0 / 60.0)
/// ```
@MainActor
public final class Physics2D {
    /// The list of physics bodies currently in the world.
    public private(set) var bodies: [PhysicsBody2D] = []

    /// The list of constraints currently in the world.
    public private(set) var constraints: [PhysicsConstraint2D] = []

    /// The global gravitational acceleration applied to all non-static bodies each step.
    private var gravity: SIMD2<Float> = SIMD2(0, 0)

    /// The spatial hash used for broad-phase collision detection.
    private let spatialHash: SpatialHash2D

    /// The approach speed below which a contact is treated as inelastic (set per step).
    private var restitutionThreshold: Float = 0

    /// An optional bounding box that confines all bodies within its limits.
    ///
    /// When set, bodies are clamped to the `min`-`max` range on each iteration.
    /// The walls only clamp positions: unlike body-to-body contacts they ignore
    /// ``PhysicsBody2D/restitution`` and ``PhysicsBody2D/friction``, so bodies
    /// come to rest against them instead of bouncing. Add a static body with
    /// ``addRect(x:y:width:height:mass:)`` where a bouncy wall is wanted.
    public var bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?

    /// Creates a new 2D physics world.
    ///
    /// - Parameter cellSize: The cell size of the spatial hash used for
    ///   broad-phase collision detection. Larger values reduce hash overhead
    ///   but increase the number of candidate pairs to check.
    public init(cellSize: Float = 50) {
        self.spatialHash = SpatialHash2D(cellSize: cellSize)
    }

    // MARK: - ボディ作成

    /// Adds a circular physics body to the world.
    ///
    /// - Parameters:
    ///   - x: The body's initial X coordinate.
    ///   - y: The body's initial Y coordinate.
    ///   - radius: The circle's radius.
    ///   - mass: The body's mass (defaults to 1.0).
    /// - Returns: The newly created ``PhysicsBody2D`` instance.
    @discardableResult
    public func addCircle(x: Float, y: Float, radius: Float, mass: Float = 1.0) -> PhysicsBody2D {
        let body = PhysicsBody2D(x: x, y: y, shape: .circle(radius: radius), mass: mass)
        bodies.append(body)
        return body
    }

    /// Adds a rectangular physics body to the world.
    ///
    /// - Parameters:
    ///   - x: The initial X coordinate of the body's center.
    ///   - y: The initial Y coordinate of the body's center.
    ///   - width: The rectangle's width.
    ///   - height: The rectangle's height.
    ///   - mass: The body's mass (defaults to 1.0).
    /// - Returns: The newly created ``PhysicsBody2D`` instance.
    @discardableResult
    public func addRect(x: Float, y: Float, width: Float, height: Float, mass: Float = 1.0) -> PhysicsBody2D {
        let body = PhysicsBody2D(x: x, y: y, shape: .rect(width: width, height: height), mass: mass)
        bodies.append(body)
        return body
    }

    // MARK: - 力

    /// Sets the global gravitational acceleration applied to all bodies each step.
    ///
    /// - Parameters:
    ///   - x: The horizontal component of the gravity vector.
    ///   - y: The vertical component of the gravity vector.
    public func setGravity(_ x: Float, _ y: Float) {
        gravity = SIMD2(x, y)
    }

    // MARK: - 拘束

    /// Adds a distance constraint between two bodies.
    ///
    /// - Parameters:
    ///   - a: The first body.
    ///   - b: The second body.
    ///   - distance: The target distance between the two bodies. If `nil`,
    ///     the current distance at creation time is used.
    /// - Returns: The newly created ``PhysicsConstraint2D`` instance.
    @discardableResult
    public func addConstraint(_ a: PhysicsBody2D, _ b: PhysicsBody2D, distance: Float? = nil) -> PhysicsConstraint2D {
        let c = PhysicsConstraint2D(a, b, distance: distance)
        constraints.append(c)
        return c
    }

    /// Pins a body to a fixed position in world space.
    ///
    /// - Parameters:
    ///   - body: The body to pin.
    ///   - x: The X coordinate of the pin position.
    ///   - y: The Y coordinate of the pin position.
    /// - Returns: The newly created pin ``PhysicsConstraint2D`` instance.
    @discardableResult
    public func pin(_ body: PhysicsBody2D, x: Float, y: Float) -> PhysicsConstraint2D {
        let c = PhysicsConstraint2D(pin: body, x: x, y: y)
        constraints.append(c)
        return c
    }

    // MARK: - シミュレーション

    /// Advances the simulation by one time step.
    ///
    /// Applies gravity, updates positions with Verlet integration, then
    /// iteratively solves constraints and resolves collisions.
    ///
    /// - Parameters:
    ///   - dt: The time step (seconds).
    ///   - iterations: The number of constraint/collision resolution
    ///     iterations (defaults to 4). More iterations yield more stable results.
    ///     `0` integrates without solving constraints, collisions or bounds.
    ///     Negative values are ignored and the whole step is skipped.
    public func step(_ dt: Float, iterations: Int = 4) {
        // 非有限・負の dt は Verlet 積分を通じて全ボディの位置を NaN に
        // 汚染する（その後の空間ハッシュでクラッシュ/ハング）ため弾く。
        // dt == 0 は「積分せず拘束・衝突だけ解決する」用途として許可する
        guard dt.isFinite, dt >= 0 else { return }

        // 負の iterations は下の `0..<iterations` が逆順 Range となり fatalError
        // する（throws では拾えない）。重力適用と積分を終えた後にトラップして
        // 半端に進んだワールドを残さないよう、dt と同じく入口で step ごと捨てる。
        // iterations == 0 は「積分だけ行い拘束・衝突・境界を解かない」用途として
        // 許可する（dt == 0 と対）。
        // MetaphorPhysics は Core 非依存（Tier 1）で metaphorWarning を使えないため、
        // dt guard と同じく無言で返す
        guard iterations >= 0 else { return }

        // 休止接触を静定させる反発の下限（このステップで重力が生む接近速度の 1.5 倍）
        restitutionThreshold = 1.5 * simd_length(gravity) * dt * dt

        // 重力を適用
        for body in bodies {
            body.applyForce(gravity * body.mass)
        }

        // 積分（非有限になった位置はサニタイズ）
        for body in bodies {
            body.integrate(dt: dt)
            sanitizePosition(body)
        }

        // ブロードフェーズは 1 ステップ 1 回だけ構築し、反復間で候補ペアを
        // 再利用する（反復ごとのハッシュ再構築と Set/配列確保を削減）。ただし
        // 拘束（特にピン）はボディを任意距離テレポートさせ得るため、構築は
        // **最初の拘束ソルブの後** に行う。2 反復目以降の位置補正は重なりの
        // 解消分・収束方向の微修正だけで、候補集合を変えるほど大きくない
        var pairs: [(Int, Int)] = []

        // 拘束と衝突を解決
        for iteration in 0..<iterations {
            // 拘束
            for c in constraints {
                c.solve()
            }

            if iteration == 0 {
                pairs = broadphasePairs()
            }

            // 衝突解消
            for (i, j) in pairs {
                resolveCollision(bodies[i], bodies[j])
            }

            // 境界
            if let bounds = bounds {
                applyBounds(bounds)
            }
        }
    }

    /// Reverts a body whose position became non-finite (NaN/∞) to its last finite position.
    ///
    /// Prevents contamination from spreading across the whole world (spatial
    /// hash, collision resolution) when user code writes NaN directly to
    /// `position`, or when the simulation diverges under extreme forces.
    /// Velocity is reset to zero.
    private func sanitizePosition(_ body: PhysicsBody2D) {
        guard !body.position.x.isFinite || !body.position.y.isFinite else { return }
        let fallback = body.previousPosition
        if fallback.x.isFinite && fallback.y.isFinite {
            body.position = fallback
        } else {
            body.position = .zero
        }
        body.previousPosition = body.position
    }

    // MARK: - 削除

    /// Removes a body and all constraints referencing it from the world.
    ///
    /// - Parameter body: The body to remove.
    public func removeBody(_ body: PhysicsBody2D) {
        bodies.removeAll { $0 === body }
        constraints.removeAll { $0.bodyA === body || $0.bodyB === body }
    }

    /// Removes a specific constraint from the world.
    ///
    /// - Parameter constraint: The constraint to remove.
    public func removeConstraint(_ constraint: PhysicsConstraint2D) {
        constraints.removeAll { $0 === constraint }
    }

    /// Removes all bodies and constraints from the world.
    public func clear() {
        bodies.removeAll()
        constraints.removeAll()
    }

    // MARK: - プライベート

    /// Builds the spatial hash and returns broad-phase candidate pairs (once per step).
    private func broadphasePairs() -> [(Int, Int)] {
        spatialHash.clear()

        for (i, body) in bodies.enumerated() {
            let radius = boundingRadius(body)
            spatialHash.insert(index: i, position: body.position, radius: radius)
        }

        return spatialHash.queryPairs()
    }

    /// Computes the bounding radius for broad-phase insertion.
    private func boundingRadius(_ body: PhysicsBody2D) -> Float {
        switch body.shape {
        case .circle(let r): return r
        case .rect(let w, let h): return sqrt(w * w + h * h) * 0.5
        }
    }

    /// Dispatches collision resolution based on the pair of shapes.
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

    /// Resolves overlap between two circles using mass-weighted position correction.
    private func resolveCircleCircle(_ a: PhysicsBody2D, _ ra: Float, _ b: PhysicsBody2D, _ rb: Float) {
        let delta = b.position - a.position
        let dist = simd_length(delta)
        let minDist = ra + rb

        guard dist < minDist else { return }

        let normal = dist > 0.0001 ? delta / dist : SIMD2<Float>(1, 0)
        let overlap = minDist - dist

        let totalMass = (a.isStatic ? 0 : a.mass) + (b.isStatic ? 0 : b.mass)
        guard totalMass > 0 else { return }

        correctPosition(a, by: -normal * overlap * (b.isStatic ? 1 : b.mass / totalMass))
        correctPosition(b, by: normal * overlap * (a.isStatic ? 1 : a.mass / totalMass))
        applyCollisionResponse(a, b, normal: normal)
    }

    /// Resolves overlap between a circle and a rectangle using closest-point projection.
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

        let normal: SIMD2<Float>
        let overlap: Float
        if dist > 0.0001 {
            guard dist < r else { return }
            normal = diff / dist
            overlap = r - dist
        } else {
            let distances = [
                (hw - delta.x, SIMD2<Float>(1, 0)),
                (hw + delta.x, SIMD2<Float>(-1, 0)),
                (hh - delta.y, SIMD2<Float>(0, 1)),
                (hh + delta.y, SIMD2<Float>(0, -1)),
            ]
            guard let nearest = distances.min(by: { $0.0 < $1.0 }) else { return }
            normal = nearest.1
            overlap = r + max(0, nearest.0)
        }

        let totalMass = (circle.isStatic ? 0 : circle.mass) + (rect.isStatic ? 0 : rect.mass)
        guard totalMass > 0 else { return }

        correctPosition(circle, by: normal * overlap * (rect.isStatic ? 1 : rect.mass / totalMass))
        correctPosition(rect, by: -normal * overlap * (circle.isStatic ? 1 : circle.mass / totalMass))
        applyCollisionResponse(rect, circle, normal: normal)
    }

    /// Resolves overlap between two axis-aligned rectangles using the minimum penetration axis.
    private func resolveRectRect(_ a: PhysicsBody2D, _ wa: Float, _ ha: Float, _ b: PhysicsBody2D, _ wb: Float, _ hb: Float) {
        // AABB 衝突
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
            correctPosition(a, by: SIMD2(-sign * overlapX * (b.isStatic ? 1 : b.mass / totalMass), 0))
            correctPosition(b, by: SIMD2(sign * overlapX * (a.isStatic ? 1 : a.mass / totalMass), 0))
            applyCollisionResponse(a, b, normal: SIMD2(sign, 0))
        } else {
            let sign: Float = dy > 0 ? 1 : -1
            correctPosition(a, by: SIMD2(0, -sign * overlapY * (b.isStatic ? 1 : b.mass / totalMass)))
            correctPosition(b, by: SIMD2(0, sign * overlapY * (a.isStatic ? 1 : a.mass / totalMass)))
            applyCollisionResponse(a, b, normal: SIMD2(0, sign))
        }
    }

    /// Moves a body out of an overlap without turning the correction into velocity.
    ///
    /// Verlet の速度は `position - previousPosition` なので、重なり解消で位置だけ
    /// 動かすと補正量がそのまま速度になる。補正は接近分をちょうど打ち消す量なので、
    /// `applyCollisionResponse` が見る接近速度が消え、`restitution` / `friction` が
    /// 一度も適用されなかった（#755）。`previousPosition` も同量ずらして速度を不変に保つ。
    private func correctPosition(_ body: PhysicsBody2D, by delta: SIMD2<Float>) {
        guard !body.isStatic else { return }
        body.position += delta
        body.previousPosition += delta
    }

    /// Applies the restitution/friction impulse by rewriting Verlet's `previousPosition`.
    ///
    /// 速度は 1 ステップあたりの変位（px/step）なので、インパルスも同じ単位で
    /// 扱い、最後に `previousPosition` を置き直して反映する。
    private func applyCollisionResponse(_ a: PhysicsBody2D, _ b: PhysicsBody2D, normal: SIMD2<Float>) {
        let invMassA = inverseMass(a)
        let invMassB = inverseMass(b)
        let invMassSum = invMassA + invMassB
        guard invMassSum > 0 else { return }

        var velocityA = a.velocity
        var velocityB = b.velocity
        let relativeVelocity = velocityB - velocityA
        let normalSpeed = simd_dot(relativeVelocity, normal)
        guard normalSpeed < 0 else { return }

        // 床に載ったボディは重力で毎ステップ `g * dt^2` だけ接近する。これを跳ね返すと
        // 休止接触が永久に微振動するので、1 ステップ分の重力による接近は反発させない
        // （摩擦は下で従来どおり効く）。重力ゼロのワールドでは閾値も 0 になる。
        let restitution = -normalSpeed <= restitutionThreshold ? 0 : min(a.restitution, b.restitution)
        let impulseMagnitude = -(1 + restitution) * normalSpeed / invMassSum
        let impulse = impulseMagnitude * normal

        if !a.isStatic { velocityA -= impulse * invMassA }
        if !b.isStatic { velocityB += impulse * invMassB }

        let updatedRelativeVelocity = velocityB - velocityA
        let tangentVelocity = updatedRelativeVelocity - simd_dot(updatedRelativeVelocity, normal) * normal
        let tangentLength = simd_length(tangentVelocity)
        if tangentLength > 0.0001 {
            let tangent = tangentVelocity / tangentLength
            let friction = (a.friction + b.friction) * 0.5
            let tangentImpulseMagnitude = -simd_dot(updatedRelativeVelocity, tangent) / invMassSum
            let maxFrictionImpulse = impulseMagnitude * friction
            let clampedTangentImpulse = max(-maxFrictionImpulse, min(maxFrictionImpulse, tangentImpulseMagnitude))
            let tangentImpulse = clampedTangentImpulse * tangent

            if !a.isStatic { velocityA -= tangentImpulse * invMassA }
            if !b.isStatic { velocityB += tangentImpulse * invMassB }
        }

        if !a.isStatic { a.previousPosition = a.position - velocityA }
        if !b.isStatic { b.previousPosition = b.position - velocityB }
    }

    private func inverseMass(_ body: PhysicsBody2D) -> Float {
        body.isStatic ? 0 : 1 / body.mass
    }

    /// Clamps all non-static bodies within the world bounds, accounting for shape size.
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
