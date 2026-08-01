import simd

/// Provides broad-phase collision detection using a uniform spatial hash grid.
///
/// Objects are inserted into grid cells based on their bounding extent.
/// After insertion, `queryPairs()` returns all unique index pairs that
/// share at least one cell, which are then tested in the narrow phase.
///
/// For best performance, choose a cell size close to the diameter of the
/// largest object in the simulation.
@MainActor
public final class SpatialHash2D {
    /// The side length of each grid cell.
    private let cellSize: Float

    /// The grid mapping from cell hash key to array of body indices.
    private var grid: [Int64: [Int]] = [:]  // hash -> ボディインデックス

    /// Creates a new spatial hash with the given cell size.
    ///
    /// - Parameter cellSize: The side length of each grid cell (defaults to 50).
    public init(cellSize: Float = 50) {
        self.cellSize = cellSize
    }

    /// Removes all entries from the grid while retaining its allocated capacity.
    func clear() {
        grid.removeAll(keepingCapacity: true)
    }

    /// Inserts a body into the grid cells covered by its bounding circle.
    ///
    /// - Parameters:
    ///   - index: The body's index in the physics world's body array.
    ///   - position: The body's center position.
    ///   - radius: The body's bounding radius.
    func insert(index: Int, position: SIMD2<Float>, radius: Float) {
        // 非有限値（NaN/∞）は Int(floor(...)) が実行時トラップになるため挿入しない
        // （そのボディはこのステップのブロードフェーズから外れるだけ）
        guard position.x.isFinite, position.y.isFinite, radius.isFinite else { return }
        let r = max(0, radius)

        let minX = cellIndex(position.x - r)
        var maxX = cellIndex(position.x + r)
        let minY = cellIndex(position.y - r)
        var maxY = cellIndex(position.y + r)

        // 巨大な半径で二重ループが爆発（ハング・メモリ枯渇）しないよう、
        // 1 ボディが占められるセル数を軸あたりで制限する（中心セル基準で
        // クランプ）。上限に当たるのは radius が cellSize の数十倍を超える
        // 縮退した構成だけで、その場合も中心近傍の候補判定は維持される
        let half = 32
        let centerX = cellIndex(position.x)
        let centerY = cellIndex(position.y)
        var clampedMinX = minX
        var clampedMinY = minY
        if maxX - minX >= half * 2 {
            clampedMinX = centerX - half
            maxX = centerX + half
        }
        if maxY - minY >= half * 2 {
            clampedMinY = centerY - half
            maxY = centerY + half
        }

        for x in clampedMinX...maxX {
            for y in clampedMinY...maxY {
                let key = Int64(x) << 32 | Int64(y) & 0xFFFFFFFF
                grid[key, default: []].append(index)
            }
        }
    }

    /// Converts a coordinate to a cell index.
    ///
    /// Clamps the index to ±10^9 (which also fits within the key's 32-bit
    /// packing) so that `Int(...)` doesn't trap even for huge finite
    /// `Float` values (> `Int.max`).
    private func cellIndex(_ value: Float) -> Int {
        let scaled = floor(value / cellSize)
        let clamped = min(max(scaled, -1_000_000_000), 1_000_000_000)
        return Int(clamped)
    }

    /// Returns all unique body index pairs that share at least one grid cell.
    ///
    /// Each pair `(a, b)` appears exactly once, with `a < b`. These pairs
    /// are candidates for narrow-phase collision testing.
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
