import Testing
import simd
@testable import MetaphorPhysics

// MARK: - Physics2D Basic Tests

@Suite("Physics2D")
@MainActor
struct Physics2DTests {

    @Test("Default initialization")
    func defaultInit() {
        let physics = Physics2D()
        #expect(physics.bodies.isEmpty)
    }

    @Test("Custom cell size initialization")
    func customCellSize() {
        let physics = Physics2D(cellSize: 100)
        #expect(physics.bodies.isEmpty)
    }

    @Test("Add body")
    func addBody() {
        let physics = Physics2D()
        let body = physics.addCircle(x: 0, y: 0, radius: 10)
        #expect(physics.bodies.count == 1)
        #expect(body.position.x == 0)
        #expect(body.position.y == 0)
    }

    @Test("Remove body")
    func removeBody() {
        let physics = Physics2D()
        let body = physics.addCircle(x: 0, y: 0, radius: 10)
        physics.removeBody(body)
        #expect(physics.bodies.isEmpty)
    }

    @Test("Step does not crash with no bodies")
    func stepEmpty() {
        let physics = Physics2D()
        physics.step(1.0 / 60.0)
        #expect(physics.bodies.isEmpty)
    }

    @Test("Gravity affects body position")
    func gravityEffect() {
        let physics = Physics2D()
        physics.setGravity(0, 100)
        let body = physics.addCircle(x: 0, y: 0, radius: 10)
        body.isStatic = false

        let initialY = body.position.y
        physics.step(1.0 / 60.0)

        #expect(body.position.y > initialY)
    }

    @Test("addRect creates rect body")
    func addRect() {
        let physics = Physics2D()
        let body = physics.addRect(x: 10, y: 20, width: 50, height: 30)
        #expect(physics.bodies.count == 1)
        #expect(body.position.x == 10)
        #expect(body.position.y == 20)
        if case .rect(let w, let h) = body.shape {
            #expect(w == 50)
            #expect(h == 30)
        } else {
            Issue.record("Expected rect shape")
        }
    }

    @Test("addCircle creates circle body")
    func addCircle() {
        let physics = Physics2D()
        let body = physics.addCircle(x: 5, y: 10, radius: 25)
        if case .circle(let r) = body.shape {
            #expect(r == 25)
        } else {
            Issue.record("Expected circle shape")
        }
    }

    @Test("static body does not move under gravity")
    func staticBodyNoMove() {
        let physics = Physics2D()
        physics.setGravity(0, 100)
        let body = physics.addCircle(x: 50, y: 50, radius: 10)
        body.isStatic = true

        physics.step(1.0 / 60.0)
        #expect(body.position.x == 50)
        #expect(body.position.y == 50)
    }

    @Test("constraint creation")
    func constraintCreation() {
        let physics = Physics2D()
        let a = physics.addCircle(x: 0, y: 0, radius: 5)
        let b = physics.addCircle(x: 10, y: 0, radius: 5)
        let constraint = physics.addConstraint(a, b, distance: 10)
        #expect(physics.constraints.count == 1)
        #expect(constraint.targetDistance == 10)
    }

    @Test("pin constraint")
    func pinConstraint() {
        let physics = Physics2D()
        let body = physics.addCircle(x: 0, y: 0, radius: 5)
        let pin = physics.pin(body, x: 0, y: 0)
        #expect(physics.constraints.count == 1)
        #expect(pin.pinPosition != nil)
    }

    @Test("pin-teleported body collides within the same step")
    func pinTeleportCollidesSameStep() {
        // 回帰テスト（#219）: ブロードフェーズ候補を拘束ソルブの前に構築すると、
        // ピン拘束で遠くから移動してきたボディの衝突がそのステップで見逃される。
        let physics = Physics2D()
        let a = physics.addCircle(x: 0, y: 0, radius: 10)
        let b = physics.addCircle(x: 100, y: 100, radius: 10)
        physics.pin(a, x: 100, y: 100)

        physics.step(1.0 / 60.0)

        let dist = simd_length(b.position - a.position)
        #expect(dist > 1.0, "ピンで重ねられた 2 円が同一ステップ内で分離すること: dist=\(dist)")
    }

    @Test("removeConstraint")
    func removeConstraint() {
        let physics = Physics2D()
        let a = physics.addCircle(x: 0, y: 0, radius: 5)
        let b = physics.addCircle(x: 10, y: 0, radius: 5)
        let c = physics.addConstraint(a, b)
        physics.removeConstraint(c)
        #expect(physics.constraints.isEmpty)
    }

    @Test("clear removes all bodies and constraints")
    func clear() {
        let physics = Physics2D()
        let a = physics.addCircle(x: 0, y: 0, radius: 5)
        let b = physics.addCircle(x: 10, y: 0, radius: 5)
        _ = physics.addConstraint(a, b)
        physics.clear()
        #expect(physics.bodies.isEmpty)
        #expect(physics.constraints.isEmpty)
    }

    @Test("multiple substeps")
    func multipleSubsteps() {
        let physics = Physics2D()
        physics.setGravity(0, 100)
        let body = physics.addCircle(x: 0, y: 0, radius: 10)
        body.isStatic = false

        physics.step(1.0 / 60.0, iterations: 8)
        #expect(body.position.y > 0)
    }

    @Test("body applyForce changes velocity")
    func applyForce() {
        let physics = Physics2D()
        let body = physics.addCircle(x: 0, y: 0, radius: 5)
        body.isStatic = false
        body.applyForce(SIMD2(100, 0))
        physics.step(1.0 / 60.0)
        #expect(body.position.x > 0)
    }

    @Test("body restitution and friction properties")
    func bodyProperties() {
        let body = PhysicsBody2D(x: 0, y: 0, shape: .circle(radius: 10))
        #expect(body.restitution == 0.5)
        #expect(body.friction == 0.1)
        body.restitution = 0.8
        body.friction = 0.3
        #expect(body.restitution == 0.8)
        #expect(body.friction == 0.3)
    }

    @Test("mass is sanitized to avoid NaN forces")
    func massSanitization() {
        let body = PhysicsBody2D(x: 0, y: 0, shape: .circle(radius: 10), mass: 0)
        #expect(body.mass > 0)

        body.applyForce(SIMD2<Float>(1, 0))
        #expect(body.acceleration.x.isFinite)

        body.mass = -10
        #expect(body.mass > 0)
    }

    @Test("circle centered inside rect is pushed out")
    func circleInsideRectResolves() {
        let physics = Physics2D(cellSize: 100)
        let rect = physics.addRect(x: 0, y: 0, width: 10, height: 10)
        rect.isStatic = true
        let circle = physics.addCircle(x: 0, y: 0, radius: 2)

        physics.step(0, iterations: 1)

        #expect(abs(circle.position.x) >= 7 || abs(circle.position.y) >= 7)
    }
}

// MARK: - 衝突応答（#755）

/// `restitution` / `friction` が衝突後の速度に現れることを確かめる。
///
/// 速度は Verlet の位置差（1 ステップあたりの変位）なので、初速は
/// `previousPosition` を直接置いて与える。位置補正が速度に化けていた頃は
/// これらの値がすべて 0（あるいは押し戻し量そのもの）になっていた。
@Suite("Physics2D collision response")
@MainActor
struct Physics2DCollisionResponseTests {

    /// 床にちょうど接した円へ、既知の下向き接近速度だけを与えて 1 ステップ進める。
    private func bounceBackFromRect(approach v: Float, restitution: Float = 0.9) -> Float {
        let physics = Physics2D(cellSize: 100)
        let floor = physics.addRect(x: 0, y: -50, width: 400, height: 100)  // 上面 y = 0
        floor.isStatic = true
        floor.restitution = restitution
        floor.friction = 0

        let ball = physics.addCircle(x: 0, y: 10, radius: 10)
        ball.restitution = restitution
        ball.friction = 0
        ball.previousPosition = SIMD2(0, 10 + v)

        physics.step(1.0 / 60.0)
        return ball.velocity.y
    }

    @Test("restitution bounces a circle off a static rect", arguments: [Float(0.5), 4.0, 20.0])
    func circleRectRestitution(approach: Float) {
        let bounce = bounceBackFromRect(approach: approach)
        let expected = 0.9 * approach
        #expect(abs(bounce - expected) < expected * 0.05, "接近 \(approach) → 期待 \(expected), 実測 \(bounce)")
    }

    @Test("restitution bounces a circle off another circle")
    func circleCircleRestitution() {
        let physics = Physics2D(cellSize: 100)
        let ground = physics.addCircle(x: 0, y: -100, radius: 100)  // 上端 y = 0
        ground.isStatic = true
        ground.restitution = 0.9
        ground.friction = 0

        let ball = physics.addCircle(x: 0, y: 10, radius: 10)
        ball.restitution = 0.9
        ball.friction = 0
        ball.previousPosition = SIMD2(0, 10 + 4.0)

        physics.step(1.0 / 60.0)

        #expect(abs(ball.velocity.y - 3.6) < 0.18, "期待 3.6, 実測 \(ball.velocity.y)")
    }

    /// #755 の芯: めり込ませた状態から極小の接近速度で当てる。位置補正が速度へ
    /// 混入していると、押し戻し量（5.0）がそのまま速度として出てくる。
    @Test("penetration is resolved without injecting velocity")
    func penetrationDoesNotInjectVelocity() {
        let physics = Physics2D(cellSize: 100)
        let floor = physics.addRect(x: 0, y: -50, width: 400, height: 100)
        floor.isStatic = true
        floor.restitution = 0.9
        floor.friction = 0

        let ball = physics.addCircle(x: 0, y: 5, radius: 10)  // 5 めり込んだ状態
        ball.restitution = 0.9
        ball.friction = 0
        ball.previousPosition = SIMD2(0, 5 + 0.1)

        physics.step(1.0 / 60.0)

        #expect(abs(ball.velocity.y - 0.09) < 0.01, "期待 0.09, 実測 \(ball.velocity.y)")
        #expect(abs(ball.position.y - 10) < 0.001, "床の上へ押し出される: \(ball.position.y)")
    }

    @Test("restitution 0 absorbs the approach speed")
    func zeroRestitutionDoesNotBounce() {
        let bounce = bounceBackFromRect(approach: 4.0, restitution: 0)
        #expect(abs(bounce) < 0.01, "跳ね返らない: \(bounce)")
    }

    /// 床の上を滑る円の横速度を 60 ステップ後に見る。
    private func slide(friction: Float) -> Float {
        let physics = Physics2D(cellSize: 100)
        physics.setGravity(0, -1000)

        let floor = physics.addRect(x: 0, y: -50, width: 4000, height: 100)
        floor.isStatic = true
        floor.friction = friction
        floor.restitution = 0

        let ball = physics.addCircle(x: 0, y: 10, radius: 10)
        ball.friction = friction
        ball.restitution = 0
        ball.previousPosition = SIMD2(-8, 10)  // 1 ステップあたり 8 で右へ

        for _ in 0..<60 { physics.step(1.0 / 60.0) }
        return ball.velocity.x
    }

    @Test("friction slows a sliding body, and friction 0 does not")
    func frictionSlowsSliding() {
        let frictionless = slide(friction: 0)
        let rough = slide(friction: 1)

        #expect(abs(frictionless - 8) < 0.01, "摩擦 0 は初速を保つ: \(frictionless)")
        #expect(rough < frictionless - 1, "摩擦 1 は明確に遅い: \(rough) vs \(frictionless)")
        #expect(rough >= -0.01, "摩擦で逆走しない: \(rough)")
    }

    /// 自由落下させて跳ね上がりの高さを見る。高さは速度の 2 乗に比例するので、
    /// e = 0.9 なら落差に対して 0.81 前後まで戻るのが理屈。
    @Test("a dropped ball bounces back to a height set by restitution")
    func freeFallBounceHeight() {
        let physics = Physics2D(cellSize: 100)
        physics.setGravity(0, -1000)

        let floor = physics.addRect(x: 0, y: -50, width: 400, height: 100)  // 上面 y = 0
        floor.isStatic = true
        floor.restitution = 0.9
        floor.friction = 0

        let drop: Float = 300
        let ball = physics.addCircle(x: 0, y: drop, radius: 10)
        ball.restitution = 0.9
        ball.friction = 0

        var lowest = drop
        var peakAfterBounce: Float = 0
        var bounced = false
        for _ in 0..<400 {
            physics.step(1.0 / 60.0)
            lowest = min(lowest, ball.position.y)
            if ball.velocity.y > 0 { bounced = true }
            if bounced { peakAfterBounce = max(peakAfterBounce, ball.position.y) }
        }

        let fall = drop - 10                       // 接触までの落差
        let rise = peakAfterBounce - 10            // 跳ね上がった高さ
        #expect(bounced, "跳ね返る")
        #expect(rise / fall > 0.6, "e = 0.9 に見合う高さまで戻る: 比 \(rise / fall)")
        #expect(rise / fall < 1.0, "エネルギーが増えない: 比 \(rise / fall)")
    }

    /// 位置補正が速度を殺さなくなると、重力で毎ステップ生まれる接近速度が
    /// 既定 restitution で跳ね返り続けかねない。休止接触が静定することを見る。
    @Test("resting contact settles instead of jittering")
    func restingContactSettles() {
        let physics = Physics2D(cellSize: 100)
        physics.setGravity(0, -1000)

        let floor = physics.addRect(x: 0, y: -50, width: 400, height: 100)
        floor.isStatic = true
        let ball = physics.addCircle(x: 0, y: 10, radius: 10)  // 既定 restitution 0.5

        for _ in 0..<120 { physics.step(1.0 / 60.0) }

        #expect(abs(ball.velocity.y) < 0.3, "床の上で静定する: \(ball.velocity.y)")
        #expect(abs(ball.position.y - 10) < 0.5, "沈まず浮かない: \(ball.position.y)")
    }
}

// MARK: - World Bounds Response Tests

/// ワールド境界の壁は「同じ係数を持つ無限質量の静的ボディ」として振る舞う（#796）。
/// 静的な床を使う `Physics2D collision response` の各ケースと対になる。
@Suite("Physics2D world bounds response")
@MainActor
struct Physics2DBoundsResponseTests {

    /// 下端にちょうど接した円へ既知の下向き接近速度を与えて 1 ステップ進める。
    ///
    /// `intoBounds` が `true` ならワールド境界の下端（`min.y = 0`）に、`false` なら
    /// 上面 `y = 0` の静的な矩形の床に当てる。どちらも接触面の位置は同じなので、
    /// 結果が一致すべき（対称性）。
    private func drop(
        intoBounds: Bool,
        approach v: Float,
        restitution: Float = 0.9,
        friction: Float = 0,
        startY: Float = 10
    ) -> PhysicsBody2D {
        let physics = Physics2D(cellSize: 100)
        if intoBounds {
            physics.bounds = (min: SIMD2(-200, 0), max: SIMD2(200, 1000))
        } else {
            let floor = physics.addRect(x: 0, y: -50, width: 400, height: 100)  // 上面 y = 0
            floor.isStatic = true
            floor.restitution = restitution
            floor.friction = friction
        }

        let ball = physics.addCircle(x: 0, y: startY, radius: 10)
        ball.restitution = restitution
        ball.friction = friction
        ball.previousPosition = SIMD2(0, startY + v)

        physics.step(1.0 / 60.0)
        return ball
    }

    /// #796 の芯: 同じ設定でも床には跳ね返るのに壁には跳ね返らない、という非対称を潰す。
    @Test("the bounds wall behaves like a static floor with the same coefficients")
    func boundsMatchesStaticFloor() {
        let onWall = drop(intoBounds: true, approach: 4.0)
        let onFloor = drop(intoBounds: false, approach: 4.0)

        #expect(
            abs(onWall.velocity.y - onFloor.velocity.y) < 0.001,
            "速度が一致する: 壁 \(onWall.velocity.y) vs 床 \(onFloor.velocity.y)"
        )
        #expect(
            abs(onWall.position.y - onFloor.position.y) < 0.001,
            "位置が一致する: 壁 \(onWall.position.y) vs 床 \(onFloor.position.y)"
        )
    }

    @Test("restitution bounces a circle off the bounds wall", arguments: [Float(0.5), 4.0, 20.0])
    func wallRestitution(approach: Float) {
        let bounce = drop(intoBounds: true, approach: approach).velocity.y
        let expected = 0.9 * approach
        #expect(abs(bounce - expected) < expected * 0.05, "接近 \(approach) → 期待 \(expected), 実測 \(bounce)")
    }

    @Test("restitution 0 absorbs the approach speed at the wall")
    func wallZeroRestitution() {
        let bounce = drop(intoBounds: true, approach: 4.0, restitution: 0).velocity.y
        #expect(abs(bounce) < 0.01, "跳ね返らない: \(bounce)")
    }

    /// クランプ量が速度に化けないこと。壁の外へ深く出た状態から極小の接近速度で当てる。
    /// `previousPosition` を動かさずに位置だけ戻すと、押し戻し量（5.1）が速度として出る。
    @Test("clamping to the wall does not inject velocity")
    func wallClampDoesNotInjectVelocity() {
        let ball = drop(intoBounds: true, approach: 0.1, startY: 5)  // 5 めり込んだ状態

        #expect(abs(ball.velocity.y - 0.09) < 0.01, "期待 0.09, 実測 \(ball.velocity.y)")
        #expect(abs(ball.position.y - 10) < 0.001, "壁の内側へ押し出される: \(ball.position.y)")
    }

    /// 壁沿いを滑る円の横速度を 60 ステップ後に見る。
    private func slideAlongWall(friction: Float) -> Float {
        let physics = Physics2D(cellSize: 100)
        physics.setGravity(0, -1000)
        physics.bounds = (min: SIMD2(-10000, 0), max: SIMD2(10000, 1000))

        let ball = physics.addCircle(x: 0, y: 10, radius: 10)
        ball.friction = friction
        ball.restitution = 0
        ball.previousPosition = SIMD2(-8, 10)  // 1 ステップあたり 8 で右へ

        for _ in 0..<60 { physics.step(1.0 / 60.0) }
        return ball.velocity.x
    }

    @Test("friction slows a body sliding along the wall, and friction 0 does not")
    func wallFriction() {
        let frictionless = slideAlongWall(friction: 0)
        let rough = slideAlongWall(friction: 1)

        #expect(abs(frictionless - 8) < 0.01, "摩擦 0 は初速を保つ: \(frictionless)")
        #expect(rough < frictionless - 1, "摩擦 1 は明確に遅い: \(rough) vs \(frictionless)")
        #expect(rough >= -0.01, "摩擦で逆走しない: \(rough)")
    }

    @Test("a ball dropped inside bounds bounces back to a height set by restitution")
    func wallFreeFallBounceHeight() {
        let physics = Physics2D(cellSize: 100)
        physics.setGravity(0, -1000)
        physics.bounds = (min: SIMD2(-200, 0), max: SIMD2(200, 1000))

        let drop: Float = 300
        let ball = physics.addCircle(x: 0, y: drop, radius: 10)
        ball.restitution = 0.9
        ball.friction = 0

        var peakAfterBounce: Float = 0
        var bounced = false
        for _ in 0..<400 {
            physics.step(1.0 / 60.0)
            if ball.velocity.y > 0 { bounced = true }
            if bounced { peakAfterBounce = max(peakAfterBounce, ball.position.y) }
            #expect(ball.position.y >= 10 - 0.001, "壁を抜けない: \(ball.position.y)")
        }

        let fall = drop - 10                       // 接触までの落差
        let rise = peakAfterBounce - 10            // 跳ね上がった高さ
        #expect(bounced, "跳ね返る")
        #expect(rise / fall > 0.6, "e = 0.9 に見合う高さまで戻る: 比 \(rise / fall)")
        #expect(rise / fall < 1.0, "エネルギーが増えない: 比 \(rise / fall)")
    }

    @Test("resting contact on the bounds wall settles instead of jittering")
    func wallRestingContactSettles() {
        let physics = Physics2D(cellSize: 100)
        physics.setGravity(0, -1000)
        physics.bounds = (min: SIMD2(-200, 0), max: SIMD2(200, 1000))

        let ball = physics.addCircle(x: 0, y: 10, radius: 10)  // 既定 restitution 0.5

        for _ in 0..<120 { physics.step(1.0 / 60.0) }

        // 落ち着いたあとの 60 ステップを見る。重力が毎ステップ生む接近を反発させると
        // 微振動が続くので、振幅で捕まえる
        var maxSpeed: Float = 0
        var maxOffset: Float = 0
        for _ in 0..<60 {
            physics.step(1.0 / 60.0)
            maxSpeed = max(maxSpeed, abs(ball.velocity.y))
            maxOffset = max(maxOffset, abs(ball.position.y - 10))
        }

        #expect(maxSpeed < 0.05, "壁の上で静定する: \(maxSpeed)")
        #expect(maxOffset < 0.05, "沈まず浮かない: \(maxOffset)")
    }

    /// 角では x / y の 2 面が同じステップで当たる。各軸が独立に反射し、
    /// 二重に跳ねてエネルギーが増えることも、押し戻しで速度が痩せることもない。
    @Test("a corner contact reflects both axes independently")
    func cornerReflectsBothAxes() {
        let physics = Physics2D(cellSize: 100)
        physics.bounds = (min: SIMD2(0, 0), max: SIMD2(200, 200))

        let ball = physics.addCircle(x: 12, y: 12, radius: 10)
        ball.restitution = 0.9
        ball.friction = 0
        ball.previousPosition = SIMD2(12 + 4, 12 + 4)  // 角へ向かって斜めに接近（各軸 4）

        physics.step(1.0 / 60.0)

        // 各軸とも e = 0.9 で反射する → (3.6, 3.6)
        #expect(abs(ball.velocity.x - 3.6) < 0.18, "x が反射する: \(ball.velocity.x)")
        #expect(abs(ball.velocity.y - 3.6) < 0.18, "y が反射する: \(ball.velocity.y)")
        #expect(abs(ball.position.x - 10) < 0.001 && abs(ball.position.y - 10) < 0.001, "角の内側へ収まる: \(ball.position)")
    }
}

// MARK: - SpatialHash2D Tests

@Suite("SpatialHash2D")
@MainActor
struct SpatialHash2DTests {

    @Test("empty hash returns no pairs")
    func emptyHash() {
        let hash = SpatialHash2D(cellSize: 50)
        let pairs = hash.queryPairs()
        #expect(pairs.isEmpty)
    }

    @Test("insert and query nearby bodies")
    func insertAndQuery() {
        let hash = SpatialHash2D(cellSize: 50)
        hash.insert(index: 0, position: SIMD2(10, 10), radius: 5)
        hash.insert(index: 1, position: SIMD2(15, 10), radius: 5)
        let pairs = hash.queryPairs()
        #expect(pairs.count >= 1)
    }

    @Test("distant bodies produce no pairs")
    func distantBodies() {
        let hash = SpatialHash2D(cellSize: 50)
        hash.insert(index: 0, position: SIMD2(0, 0), radius: 5)
        hash.insert(index: 1, position: SIMD2(1000, 1000), radius: 5)
        let pairs = hash.queryPairs()
        #expect(pairs.isEmpty)
    }

    @Test("clear removes all entries")
    func clearEntries() {
        let hash = SpatialHash2D(cellSize: 50)
        hash.insert(index: 0, position: SIMD2(10, 10), radius: 5)
        hash.clear()
        let pairs = hash.queryPairs()
        #expect(pairs.isEmpty)
    }
}

// MARK: - 非有限値の堅牢性（#142）

@Suite("Physics2D non-finite robustness")
@MainActor
struct PhysicsNonFiniteTests {

    @Test("NaN dt does not corrupt or crash the world")
    func nanDt() {
        let world = Physics2D(cellSize: 50)
        world.setGravity(0, 980)
        let ball = world.addCircle(x: 100, y: 100, radius: 20)

        // 修正前は Verlet 積分で位置が NaN になり、空間ハッシュの
        // Int(floor(NaN)) でトラップしていた
        world.step(Float.nan)
        world.step(Float.infinity)
        world.step(-1)
        world.step(0)

        #expect(ball.position.x.isFinite && ball.position.y.isFinite)

        // その後の正常な step は機能する
        world.step(1.0 / 60.0)
        #expect(ball.position.y > 100)
    }

    @Test("NaN body position is sanitized instead of crashing")
    func nanPosition() {
        let world = Physics2D(cellSize: 50)
        let a = world.addCircle(x: 100, y: 100, radius: 20)
        let b = world.addCircle(x: 110, y: 100, radius: 20)
        world.step(1.0 / 60.0)

        a.position = SIMD2(Float.nan, Float.nan)
        world.step(1.0 / 60.0)

        #expect(a.position.x.isFinite && a.position.y.isFinite)
        #expect(b.position.x.isFinite && b.position.y.isFinite)
    }

    @Test("huge radius insert does not hang")
    func hugeRadiusInsert() {
        let hash = SpatialHash2D(cellSize: 50)
        // 修正前は (2 * 3e8 / 50)^2 セルの二重ループでハング/メモリ枯渇
        hash.insert(index: 0, position: SIMD2(0, 0), radius: 3e8)
        hash.insert(index: 1, position: SIMD2(0, 0), radius: 5)
        #expect(hash.queryPairs().count >= 1)
    }

    @Test("non-finite insert values are ignored without trapping")
    func nonFiniteInsert() {
        let hash = SpatialHash2D(cellSize: 50)
        hash.insert(index: 0, position: SIMD2(Float.nan, 0), radius: 5)
        hash.insert(index: 1, position: SIMD2(0, Float.infinity), radius: 5)
        hash.insert(index: 2, position: SIMD2(0, 0), radius: Float.nan)
        // 有限巨大値（> Int.max）も Int 変換でトラップしない
        hash.insert(index: 3, position: SIMD2(3e38, -3e38), radius: 5)
        #expect(hash.queryPairs().isEmpty)
    }

    @Test("negative iterations are rejected without trapping or half-updating the world", arguments: [-1, -4, Int.min])
    func negativeIterations(iterations: Int) {
        let world = Physics2D(cellSize: 50)
        world.setGravity(0, 980)
        let ball = world.addCircle(x: 100, y: 100, radius: 20)
        let before = ball.position

        // 修正前は重力適用と積分を終えた後に `0..<iterations` を構築し、
        // 「Range requires lowerBound <= upperBound」でトラップしていた
        world.step(1.0 / 60.0, iterations: iterations)

        // dt の guard と同じく、無効入力ではワールドを一切進めない
        #expect(ball.position == before)

        // その後の正常な step は機能する
        world.step(1.0 / 60.0)
        #expect(ball.position.y > before.y)
    }

    @Test("zero iterations integrates but solves nothing")
    func zeroIterations() {
        let world = Physics2D(cellSize: 50)
        world.setGravity(0, 980)
        let ball = world.addCircle(x: 100, y: 100, radius: 20)

        world.step(1.0 / 60.0, iterations: 0)

        // 積分は行われる（拘束・衝突・境界だけを解かない）
        #expect(ball.position.y > 100)
        #expect(ball.position.x.isFinite && ball.position.y.isFinite)
    }

    @Test("constraint stiffness is clamped to [0, 1]")
    func stiffnessClamped() {
        let world = Physics2D()
        let a = world.addCircle(x: 0, y: 0, radius: 5)
        let b = world.addCircle(x: 50, y: 0, radius: 5)
        let c = world.addConstraint(a, b, distance: 50)

        c.stiffness = 2.5
        #expect(c.stiffness == 1.0)
        c.stiffness = -1.0
        #expect(c.stiffness == 0.0)
        c.stiffness = Float.nan
        #expect(c.stiffness == 1.0)
        c.stiffness = 0.5
        #expect(c.stiffness == 0.5)
    }
}

// MARK: - PhysicsConstraint2D solve()（#149: 純ロジックのカバレッジ）

@Suite("PhysicsConstraint2D Solve")
@MainActor
struct PhysicsConstraint2DSolveTests {

    @Test("distance constraint pulls both bodies symmetrically")
    func distanceConstraintSymmetric() {
        let a = PhysicsBody2D(x: 0, y: 0, shape: .circle(radius: 1))
        let b = PhysicsBody2D(x: 10, y: 0, shape: .circle(radius: 1))
        let c = PhysicsConstraint2D(a, b, distance: 4)

        c.solve()

        // 距離 10 → 目標 4: 差 6 を両側で半分ずつ補正（stiffness 1.0）
        #expect(abs(a.position.x - 3) < 0.001, "a は +3 へ移動: \(a.position)")
        #expect(abs(b.position.x - 7) < 0.001, "b は -3 へ移動: \(b.position)")
        #expect(abs(simd_length(b.position - a.position) - 4) < 0.001)
    }

    @Test("default distance is the current separation")
    func defaultDistanceIsCurrent() {
        let a = PhysicsBody2D(x: 0, y: 0, shape: .circle(radius: 1))
        let b = PhysicsBody2D(x: 3, y: 4, shape: .circle(radius: 1))
        let c = PhysicsConstraint2D(a, b)
        #expect(abs(c.targetDistance - 5) < 0.001)

        // 既に目標距離なので solve() しても動かない
        c.solve()
        #expect(a.position == SIMD2<Float>(0, 0))
        #expect(b.position == SIMD2<Float>(3, 4))
    }

    @Test("static body does not move; the other body absorbs the correction")
    func staticBodyDoesNotMove() {
        let a = PhysicsBody2D(x: 0, y: 0, shape: .circle(radius: 1))
        a.isStatic = true
        let b = PhysicsBody2D(x: 10, y: 0, shape: .circle(radius: 1))
        let c = PhysicsConstraint2D(a, b, distance: 4)

        c.solve()

        #expect(a.position == SIMD2<Float>(0, 0), "static ボディは動かない")
        // b のみが補正される（対称補正の半分 = 3 だけ動く実装仕様）
        #expect(abs(b.position.x - 7) < 0.001)
    }

    @Test("pin constraint moves the body toward the anchor by stiffness")
    func pinConstraint() {
        let body = PhysicsBody2D(x: 0, y: 0, shape: .circle(radius: 1))
        let c = PhysicsConstraint2D(pin: body, x: 10, y: 0)

        c.solve()
        #expect(abs(body.position.x - 10) < 0.001, "stiffness 1.0 で即座にピン位置へ")

        // ソフトピン（stiffness 0.5）は中間まで
        let body2 = PhysicsBody2D(x: 0, y: 0, shape: .circle(radius: 1))
        let c2 = PhysicsConstraint2D(pin: body2, x: 10, y: 0)
        c2.stiffness = 0.5
        c2.solve()
        #expect(abs(body2.position.x - 5) < 0.001)
    }

    @Test("coincident bodies do not produce NaN")
    func coincidentBodies() {
        let a = PhysicsBody2D(x: 5, y: 5, shape: .circle(radius: 1))
        let b = PhysicsBody2D(x: 5, y: 5, shape: .circle(radius: 1))
        let c = PhysicsConstraint2D(a, b, distance: 4)

        c.solve()
        #expect(a.position.x.isFinite && a.position.y.isFinite)
        #expect(b.position.x.isFinite && b.position.y.isFinite)
    }

    @Test("non-finite stiffness resets to 1.0")
    func nonFiniteStiffness() {
        let a = PhysicsBody2D(x: 0, y: 0, shape: .circle(radius: 1))
        let c = PhysicsConstraint2D(pin: a, x: 1, y: 1)
        c.stiffness = .nan
        #expect(c.stiffness == 1.0)
        c.stiffness = 2.0
        #expect(c.stiffness == 1.0)
        c.stiffness = -1.0
        #expect(c.stiffness == 0.0)
    }
}

// MARK: - 固定刻みのアキュムレータ（#756）

/// 実フレーム時間は常に揺れる。Verlet は速度を「1 ステップあたりの変位」で持つので、
/// 揺れた dt をそのまま `step` へ渡すとエネルギーが出入りし、同じスケッチが実行のたびに
/// 違う動きになる。`advance` は経過時間を溜めて固定刻みで消化することでこれを断つ。
@Suite("Physics2D fixed timestep")
@MainActor
struct Physics2DFixedTimestepTests {

    /// 自由落下だけの世界を作る（拘束・衝突は挟まない）。
    private func makeFallingWorld() -> (Physics2D, PhysicsBody2D) {
        let world = Physics2D(cellSize: 50)
        world.setGravity(0, -1000)
        let body = world.addCircle(x: 0, y: 0, radius: 1)
        return (world, body)
    }

    /// 一定刻みと、平均は同じでジッタのある刻み。合計時間はどちらも 10 秒。
    private static let steadySteps = [Float](repeating: 1.0 / 60.0, count: 600)
    private static let jitteredSteps: [Float] =
        (0..<600).map { $0 % 2 == 0 ? 1.0 / 120.0 : 1.0 / 40.0 }

    @Test("advance() makes the fall independent of frame-time jitter")
    func advanceAbsorbsJitter() {
        let (steadyWorld, steadyBody) = makeFallingWorld()
        for dt in Self.steadySteps { steadyWorld.advance(dt, iterations: 0) }

        let (jitteredWorld, jitteredBody) = makeFallingWorld()
        for dt in Self.jitteredSteps { jitteredWorld.advance(dt, iterations: 0) }

        let steady = steadyBody.position.y
        let jittered = jitteredBody.position.y
        #expect(steady < -1000, "そもそも落ちていること")
        // 許容差 1% 未満（素の step() だと 25% ずれる）
        #expect(abs(jittered - steady) / abs(steady) < 0.01)
    }

    // 失敗系: 低レベル API の step() は今までどおり dt の揺れをそのまま食らう。
    // これが advance() の存在理由なので、揺れが消えたら doc ごと見直す合図になる。

    @Test("step() still integrates whatever dt it is given")
    func stepIsSensitiveToJitter() {
        let (steadyWorld, steadyBody) = makeFallingWorld()
        for dt in Self.steadySteps { steadyWorld.step(dt, iterations: 0) }

        let (jitteredWorld, jitteredBody) = makeFallingWorld()
        for dt in Self.jitteredSteps { jitteredWorld.step(dt, iterations: 0) }

        let ratio = jitteredBody.position.y / steadyBody.position.y
        #expect(ratio > 1.2)
    }

    @Test("advance() keeps leftover time for the next call")
    func advanceCarriesRemainder() {
        let (world, body) = makeFallingWorld()
        // fixedTimeStep の 1/4 ずつ渡す。3 回目までは 1 ステップも走らない
        let quarter = world.fixedTimeStep / 4
        for _ in 0..<3 { world.advance(quarter, iterations: 0) }
        #expect(body.position.y == 0)

        // 4 回目で溜まりが 1 ステップぶんに届く
        world.advance(quarter, iterations: 0)
        #expect(body.position.y < 0)

        // 同じ時間を 1 回で渡したときと一致する（溜め方で結果が変わらない）
        let (reference, referenceBody) = makeFallingWorld()
        reference.advance(world.fixedTimeStep, iterations: 0)
        #expect(abs(body.position.y - referenceBody.position.y) < 1e-6)
    }

    // 境界値: 長すぎるフレームは打ち切ってスパイラルを避ける

    @Test("advance() caps the sub-steps of one call")
    func advanceCapsSubSteps() {
        let (world, body) = makeFallingWorld()
        world.maxSubSteps = 4
        // 上限の 100 倍の時間を渡しても 4 ステップぶんしか進まない
        world.advance(world.fixedTimeStep * 400, iterations: 0)

        let (reference, referenceBody) = makeFallingWorld()
        for _ in 0..<4 { reference.step(reference.fixedTimeStep, iterations: 0) }
        #expect(abs(body.position.y - referenceBody.position.y) < 1e-6)

        // 打ち切ったぶんは持ち越さない（次の呼び出しが取り返そうとしない）
        world.advance(0, iterations: 0)
        #expect(abs(body.position.y - referenceBody.position.y) < 1e-6)
    }

    @Test("advance() ignores non-finite and negative elapsed time")
    func advanceRejectsBadElapsed() {
        let (world, body) = makeFallingWorld()
        for bad in [Float.nan, .infinity, -1.0 / 60.0] {
            world.advance(bad, iterations: 0)
        }
        #expect(body.position.y == 0)
        #expect(body.position.x.isFinite && body.position.y.isFinite)

        // 負の iterations も step() と同じく丸ごと捨てる
        world.advance(1.0, iterations: -1)
        #expect(body.position.y == 0)

        // 弾いた値がアキュムレータを汚していないこと。NaN を足していたら
        // 以降 `accumulator >= fixedTimeStep` が永久に偽になり、物理が無言で死ぬ。
        world.advance(world.fixedTimeStep, iterations: 0)
        let (reference, referenceBody) = makeFallingWorld()
        reference.step(reference.fixedTimeStep, iterations: 0)
        #expect(abs(body.position.y - referenceBody.position.y) < 1e-6)
        #expect(body.position.y < 0)
    }

    @Test("fixedTimeStep and maxSubSteps sanitize invalid values")
    func settingsAreSanitized() {
        let world = Physics2D(cellSize: 50)
        let defaultStep = world.fixedTimeStep
        #expect(abs(defaultStep - 1.0 / 120.0) < 1e-9)

        world.fixedTimeStep = 1.0 / 240.0
        #expect(abs(world.fixedTimeStep - 1.0 / 240.0) < 1e-9)
        for bad in [Float.nan, 0, -1] {
            world.fixedTimeStep = bad
            #expect(world.fixedTimeStep == defaultStep)
            world.fixedTimeStep = 1.0 / 240.0
        }

        #expect(world.maxSubSteps == 8)
        world.maxSubSteps = 0
        #expect(world.maxSubSteps == 1, "0 だと物理が止まるので 1 へ切り上げる")
        world.maxSubSteps = -5
        #expect(world.maxSubSteps == 1)
        world.maxSubSteps = 16
        #expect(world.maxSubSteps == 16)
    }
}
