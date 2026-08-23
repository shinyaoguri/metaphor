import MetaphorCore
import MetaphorPhysics

// MARK: - 物理ブリッジ

extension Sketch {
    /// Creates a 2D physics simulation world.
    ///
    /// - Parameter cellSize: The spatial hash cell size used for broad-phase collision detection.
    /// - Returns: A new ``MetaphorPhysics/Physics2D`` instance.
    public func createPhysics2D(cellSize: Float = 50) -> Physics2D {
        guard cellSize > 0 else {
            metaphorWarning(
                "createPhysics2D: cellSize must be positive (got \(cellSize)); using 50")
            return Physics2D(cellSize: 50)
        }
        return Physics2D(cellSize: cellSize)
    }
}

// MARK: - Node ↔ Physics2D ブリッジ

extension Node {
    /// Syncs this node's XY position from a 2D physics body.
    ///
    /// The Z position is preserved. Call it every frame, after `physics.step()`.
    ///
    /// - Parameter body: The physics body to read the position from.
    public func syncFromPhysics(_ body: PhysicsBody2D) {
        position = SIMD3(body.position.x, body.position.y, position.z)
    }

    /// Writes this node's XY position back to a 2D physics body.
    ///
    /// Use it to teleport the body to the node's position.
    ///
    /// - Parameter body: The physics body to write the position to.
    public func syncToPhysics(_ body: PhysicsBody2D) {
        body.position = SIMD2(position.x, position.y)
        body.previousPosition = body.position
    }
}
