import simd

/// 均一な空間ハッシュグリッドを使用したブロードフェーズ衝突検出を提供します。
///
/// オブジェクトはバウンディング範囲に基づいてグリッドセルに挿入されます。
/// 挿入後、`queryPairs()` は少なくとも1つのセルを共有するすべてのユニークな
/// インデックスペアを返し、それらがナローフェーズでテストされます。
///
/// セルサイズは最適なパフォーマンスのために、シミュレーション内の最大オブジェクトの
/// 直径とほぼ同じに選択してください。
@MainActor
public final class SpatialHash2D {
    /// 各グリッドセルの辺の長さ。
    private let cellSize: Float

    /// セルハッシュキーからボディインデックス配列へのグリッドマッピング。
    private var grid: [Int64: [Int]] = [:]  // hash -> ボディインデックス

    /// 指定セルサイズで新しい空間ハッシュを作成します。
    ///
    /// - Parameter cellSize: 各グリッドセルの辺の長さ（デフォルトは50）。
    public init(cellSize: Float = 50) {
        self.cellSize = cellSize
    }

    /// 確保済み容量を保持しつつ、グリッドからすべてのエントリを削除します。
    func clear() {
        grid.removeAll(keepingCapacity: true)
    }

    /// バウンディング円がカバーするグリッドセルにボディを挿入します。
    ///
    /// - Parameters:
    ///   - index: 物理ワールドのボディ配列におけるボディのインデックス。
    ///   - position: ボディの中心位置。
    ///   - radius: ボディのバウンディング半径。
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

    /// 少なくとも1つのグリッドセルを共有するすべてのユニークなボディインデックスペアを返します。
    ///
    /// 各ペア `(a, b)` は `a < b` で正確に1回だけ出現します。
    /// これらのペアはナローフェーズ衝突テストの候補です。
    ///
    /// - Returns: ユニークな `(Int, Int)` インデックスペアの配列。
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
