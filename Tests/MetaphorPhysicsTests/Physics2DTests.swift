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
        physics.addGravity(0, 100)
        let body = physics.addCircle(x: 0, y: 0, radius: 10)
        body.isStatic = false

        let initialY = body.position.y
        physics.step(1.0 / 60.0)

        #expect(body.position.y > initialY)
    }
}
