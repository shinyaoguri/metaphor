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

    /// 座標をセルインデックスへ変換します。
    ///
    /// Float の有限巨大値（> Int.max）でも `Int(...)` がトラップしないよう、
    /// インデックスを ±10^9 にクランプする（キーの 32bit パッキングにも収まる）。
    private func cellIndex(_ value: Float) -> Int {
        let scaled = floor(value / cellSize)
        let clamped = min(max(scaled, -1_000_000_000), 1_000_000_000)
        return Int(clamped)
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
