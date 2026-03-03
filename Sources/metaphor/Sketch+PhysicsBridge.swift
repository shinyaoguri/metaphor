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
