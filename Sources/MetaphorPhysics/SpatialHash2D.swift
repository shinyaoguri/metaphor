import simd

/// Provide broad-phase collision detection using a uniform spatial hash grid.
///
/// Objects are inserted into grid cells based on their bounding extent. After
/// insertion, `queryPairs()` returns all unique pairs of indices that share
/// at least one cell, which are then tested in the narrow phase.
///
/// The cell size should be chosen to roughly match the diameter of the largest
/// object in the simulation for optimal performance.
@MainActor
public final class SpatialHash2D {
    /// The side length of each grid cell.
    private let cellSize: Float

    /// The grid mapping cell hash keys to arrays of body indices.
    private var grid: [Int64: [Int]] = [:]  // hash -> body indices

    /// Create a new spatial hash with the given cell size.
    ///
    /// - Parameter cellSize: The side length of each grid cell (defaults to 50).
    public init(cellSize: Float = 50) {
        self.cellSize = cellSize
    }

    /// Remove all entries from the grid while preserving allocated capacity.
    func clear() {
        grid.removeAll(keepingCapacity: true)
    }

    /// Insert a body into the grid cells covered by its bounding circle.
    ///
    /// - Parameters:
    ///   - index: The index of the body in the physics world's body array.
    ///   - position: The center position of the body.
    ///   - radius: The bounding radius of the body.
    func insert(index: Int, position: SIMD2<Float>, radius: Float) {
        let minX = Int(floor((position.x - radius) / cellSize))
        let maxX = Int(floor((position.x + radius) / cellSize))
        let minY = Int(floor((position.y - radius) / cellSize))
        let maxY = Int(floor((position.y + radius) / cellSize))

        for x in minX...maxX {
            for y in minY...maxY {
                let key = Int64(x) << 32 | Int64(y) & 0xFFFFFFFF
                grid[key, default: []].append(index)
            }
        }
    }

    /// Return all unique pairs of body indices that share at least one grid cell.
    ///
    /// Each pair `(a, b)` appears exactly once with `a < b`. These pairs are
    /// candidates for narrow-phase collision testing.
    ///
    /// - Returns: An array of unique `(Int, Int)` index pairs.
    func queryPairs() -> [(Int, Int)] {
        var pairs: Set<Int64> = []
        var result: [(Int, Int)] = []

        for (_, indices) in grid {
            for i in 0..<indices.count {
                for j in (i+1)..<indices.count {
                    let a = min(indices[i], indices[j])
                    let b = max(indices[i], indices[j])
                    let key = Int64(a) << 32 | Int64(b)
                    if pairs.insert(key).inserted {
                        result.append((a, b))
                    }
                }
            }
        }

        return result
    }
}
