import Testing
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
