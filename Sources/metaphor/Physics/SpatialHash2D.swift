/// 空間ハッシュによるブロードフェーズ衝突検出
@MainActor
public final class SpatialHash2D {
    private let cellSize: Float
    private var grid: [Int64: [Int]] = [:]  // hash -> body indices

    public init(cellSize: Float = 50) {
        self.cellSize = cellSize
    }

    func clear() {
        grid.removeAll(keepingCapacity: true)
    }

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
