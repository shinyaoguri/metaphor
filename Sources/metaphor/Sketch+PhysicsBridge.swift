import MetaphorCore
import MetaphorPhysics

// MARK: - Physics Bridge

extension Sketch {
    /// Create a 2D physics simulation world.
    ///
    /// - Parameter cellSize: The spatial hash cell size for broad-phase collision detection.
    /// - Returns: A new ``Physics2D`` instance.
    public func createPhysics2D(cellSize: Float = 50) -> Physics2D {
        Physics2D(cellSize: cellSize)
    }
}

// MARK: - Node ↔ Physics2D Bridge

extension Node {
    /// Synchronize this node's XY position from a 2D physics body.
    ///
    /// The Z position is preserved. Call this each frame after `physics.step()`.
    ///
    /// - Parameter body: The physics body to read position from.
    public func syncFromPhysics(_ body: PhysicsBody2D) {
        position = SIMD3(body.position.x, body.position.y, position.z)
    }

    /// Write this node's XY position back to a 2D physics body.
    ///
    /// Useful for teleporting a body to match a node's position.
    ///
    /// - Parameter body: The physics body to write position to.
    public func syncToPhysics(_ body: PhysicsBody2D) {
        body.position = SIMD2(position.x, position.y)
        body.previousPosition = body.position
    }
}
