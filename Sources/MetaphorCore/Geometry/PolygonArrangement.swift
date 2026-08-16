import Foundation

/// 自己交差する2Dポリゴンを平面分割し、ear clipping で塗れる面へ分解します。
///
/// ear clipping は単純ポリゴン専用なので、五芒星のように辺どうしが交差する頂点列を
/// そのまま渡すと耳が尽きて破綻します。ここで交点を求めて辺を割り、平面分割の各面を
/// 取り出しておけば、後段は既存の ear clipping をそのまま使えます。
/// どの面を塗るか（nonzero winding 規則）は ``EarClipTriangulator/triangulateNonZero(_:)``
/// が ``WindingCounter`` で決めます。
///
/// 交差検出は辺数 n に対して O(n^2) で、そのあとの面の抽出とテッセレーションは交点の数に
/// 比例します。自己交差が 1 つも無ければ交差検出だけで打ち切って `nil` を返すので、
/// ふつうのポリゴンでは ear clipping と同じオーダーに収まります（100頂点で数十マイクロ秒）。
/// 交点が数千に達する極端な形（{101/50} 星型多角形など）では 10 ミリ秒規模になります。
///
/// 座標は内部で `Double` に上げて扱います。交点は辺ごとに別々の式で求まるため、
/// `Float` のままだと同じ点がノードとして分かれ、面の抽出が壊れます。
enum PolygonArrangement {

    // MARK: - Result

    /// 平面分割の結果。
    struct Result {
        /// 面を構成する点（入力頂点 + 交点）。
        var points: [(Float, Float)]
        /// `points` と同じ並びの由来情報。
        var origins: [EarClipTriangulator.VertexOrigin]
        /// 有界な面。各要素は `points` を参照する CCW の閉歩道で、そのまま
        /// ``EarClipTriangulator/triangulate(_:)`` に渡せます（同じノードを 2 度通る
        /// ことがありますが、それは穴をブリッジでつないだ形なので ear clipping で扱えます）。
        var faces: [[Int]]
    }

    // MARK: - Entry Point

    /// ポリゴンを平面分割します。
    /// - Parameter polygon: 閉じているものとして扱う頂点列。
    /// - Returns: 自己交差が無ければ `nil`（呼び出し元は入力をそのまま ear clipping できます）。
    static func decompose(_ polygon: [(Float, Float)]) -> Result? {
        guard polygon.count >= 3 else { return nil }

        // 許容誤差は座標系のスケールに合わせる（ピクセル座標でも正規化座標でも効くように）。
        var low = SIMD2(Double.infinity, Double.infinity)
        var high = SIMD2(-Double.infinity, -Double.infinity)
        for v in polygon {
            guard v.0.isFinite, v.1.isFinite else { return nil }
            let p = SIMD2(Double(v.0), Double(v.1))
            low = SIMD2(Swift.min(low.x, p.x), Swift.min(low.y, p.y))
            high = SIMD2(Swift.max(high.x, p.x), Swift.max(high.y, p.y))
        }
        let extent = Swift.max(high.x - low.x, high.y - low.y)
        guard extent.isFinite, extent > 0 else { return nil }
        let tolerance = extent * 1e-7
        guard tolerance > 0 else { return nil }
        // これより小さい面は 1 ピクセルにも満たないので、橋や棘が作る潰れた面として捨てる。
        let areaTolerance = extent * tolerance

        // 1. 連続する重複頂点と、先頭に戻る終端頂点を落とす。
        var ring: [(point: SIMD2<Double>, index: Int)] = []
        for (i, v) in polygon.enumerated() {
            let p = SIMD2(Double(v.0), Double(v.1))
            if let last = ring.last, isNear(last.point, p, tolerance) { continue }
            ring.append((p, i))
        }
        while ring.count >= 2, isNear(ring[0].point, ring[ring.count - 1].point, tolerance) {
            ring.removeLast()
        }
        guard ring.count >= 3 else { return nil }
        let edgeCount = ring.count

        // 2. 頂点をノードに登録する。座標が一致する頂点があれば、交差が無くても
        //    （ループどうしが 1 点で接する形なので）平面分割に回す必要がある。
        var nodes = NodeTable(origin: low, tolerance: tolerance)
        let ringNodes = ring.map { nodes.insert($0.point, origin: .vertex($0.index)) }
        let hasCoincidentVertices = Set(ringNodes).count < edgeCount

        // 3. 全辺の総当たりで交点を求め、辺の内分比として集める。
        var edgeOrigin: [SIMD2<Double>] = []
        var edgeDelta: [SIMD2<Double>] = []
        var edgeLength: [Double] = []
        var boxLow: [SIMD2<Double>] = []
        var boxHigh: [SIMD2<Double>] = []
        for k in 0..<edgeCount {
            let a = ring[k].point
            let b = ring[(k + 1) % edgeCount].point
            let delta = b - a
            edgeOrigin.append(a)
            edgeDelta.append(delta)
            edgeLength.append(dot(delta, delta).squareRoot())
            boxLow.append(SIMD2(Swift.min(a.x, b.x), Swift.min(a.y, b.y)))
            boxHigh.append(SIMD2(Swift.max(a.x, b.x), Swift.max(a.y, b.y)))
        }

        var splits: [[Double]] = Array(repeating: [], count: edgeCount)
        for i in 0..<edgeCount {
            guard edgeLength[i] > tolerance else { continue }
            for j in (i + 1)..<edgeCount {
                guard edgeLength[j] > tolerance else { continue }
                // バウンディングボックスが離れていれば交差しない。
                if boxLow[i].x > boxHigh[j].x + tolerance || boxLow[j].x > boxHigh[i].x + tolerance { continue }
                if boxLow[i].y > boxHigh[j].y + tolerance || boxLow[j].y > boxHigh[i].y + tolerance { continue }

                let hits = intersections(
                    edgeOrigin[i], edgeDelta[i],
                    edgeOrigin[j], edgeDelta[j],
                    tolerance: tolerance
                )
                let toleranceI = tolerance / edgeLength[i]
                let toleranceJ = tolerance / edgeLength[j]
                for hit in hits {
                    // 端点に一致する交点は分割を生まない（隣接辺の共有頂点や、
                    // 辺の上に別の頂点が乗るだけの接触がここに来る）。
                    if hit.t > toleranceI, hit.t < 1 - toleranceI { splits[i].append(hit.t) }
                    if hit.u > toleranceJ, hit.u < 1 - toleranceJ { splits[j].append(hit.u) }
                }
            }
        }

        // 4. 交点も重複頂点も無ければ単純ポリゴン。従来経路へ返す。
        guard hasCoincidentVertices || splits.contains(where: { !$0.isEmpty }) else { return nil }

        // 5. 交点でノードを増やし、無向辺の集合を作る。
        //    完全に重なる辺（同じ経路を 2 度なぞる頂点列）はここで 1 本にまとまる。
        var edges: Set<UndirectedEdge> = []
        for k in 0..<edgeCount {
            let from = ring[k].index
            let to = ring[(k + 1) % edgeCount].index
            var chain = [ringNodes[k]]
            for t in splits[k].sorted() {
                let point = edgeOrigin[k] + edgeDelta[k] * t
                chain.append(nodes.insert(point, origin: .init(from: from, to: to, t: Float(t))))
            }
            chain.append(ringNodes[(k + 1) % edgeCount])
            for i in 0..<(chain.count - 1) where chain[i] != chain[i + 1] {
                edges.insert(UndirectedEdge(chain[i], chain[i + 1]))
            }
        }

        let points = nodes.points
        return Result(
            points: points.map { (Float($0.x), Float($0.y)) },
            origins: nodes.origins,
            faces: extractFaces(points: points, edges: edges, areaTolerance: areaTolerance)
        )
    }

    // MARK: - Winding

    /// 巻き数を面ごとに何度も数えるための、`Double` 化済みの入力ポリゴン。
    ///
    /// 面の数は交点の数に比例して増えるので、呼ぶたびに `Float` から変換し直すと
    /// そこが支配的になります。
    struct WindingCounter {
        private let points: [SIMD2<Double>]

        init(_ polygon: [(Float, Float)]) {
            points = polygon.map { SIMD2(Double($0.0), Double($0.1)) }
        }

        /// 点がポリゴンを何周ぶん囲んでいるか（巻き数）を返します。
        ///
        /// nonzero winding 規則ではこれが 0 でない領域が塗られます。
        /// Dan Sunday の交差数え上げ法。辺の上下判定を半開区間にすることで、
        /// 点が頂点の高さにぴったり並んでも二重に数えません。
        func windingNumber(at point: (Float, Float)) -> Int {
            let p = SIMD2(Double(point.0), Double(point.1))
            var winding = 0
            let n = points.count
            for i in 0..<n {
                let a = points[i]
                let b = points[(i + 1) % n]
                if a.y <= p.y {
                    if b.y > p.y, cross(b - a, p - a) > 0 { winding += 1 }
                } else if b.y <= p.y, cross(b - a, p - a) < 0 {
                    winding -= 1
                }
            }
            return winding
        }
    }

    // MARK: - Face Extraction

    /// 平面分割の面を取り出します。
    ///
    /// 各無向辺を両向きの半辺として扱い、「入ってきた辺の逆向きから時計回りに次の辺」を
    /// たどると、有界な面は CCW（面積が正）、外側の面は CW（面積が負）の閉歩道になります。
    /// 単一の閉じた折れ線から作ったグラフは連結なので、外側の面はちょうど 1 つです。
    private static func extractFaces(
        points: [SIMD2<Double>],
        edges: Set<UndirectedEdge>,
        areaTolerance: Double
    ) -> [[Int]] {
        guard !edges.isEmpty else { return [] }

        var adjacency: [[Int]] = Array(repeating: [], count: points.count)
        for edge in edges {
            adjacency[edge.a].append(edge.b)
            adjacency[edge.b].append(edge.a)
        }
        // 各ノードのまわりで隣接ノードを角度順に並べる。次数はたいてい 2〜4 なので、
        // 位置は毎回線形に引く（ノードごとの索引を持つとその確保のほうが高くつく）。
        for v in 0..<points.count where adjacency[v].count > 1 {
            adjacency[v].sort { lhs, rhs in
                atan2(points[lhs].y - points[v].y, points[lhs].x - points[v].x)
                    < atan2(points[rhs].y - points[v].y, points[rhs].x - points[v].x)
            }
        }

        let nodeCount = Int64(points.count)
        var visited: Set<Int64> = []
        var faces: [[Int]] = []

        for start in 0..<points.count {
            for first in adjacency[start] {
                var from = start
                var to = first
                var walk: [Int] = []
                while !visited.contains(Int64(from) * nodeCount + Int64(to)) {
                    visited.insert(Int64(from) * nodeCount + Int64(to))
                    walk.append(from)
                    guard let position = adjacency[to].firstIndex(of: from) else { break }
                    let degree = adjacency[to].count
                    let next = adjacency[to][(position + degree - 1) % degree]
                    from = to
                    to = next
                }
                // 外側の面（CW）と、橋を往復するだけの潰れた歩道をここで落とす。
                guard walk.count >= 3, signedArea(walk, points) > areaTolerance else { continue }

                // 歩道は同じノードを 2 度通ることがある（棘の往復、ループどうしが 1 点で
                // 接する形、面の内側に閉じ込められた領域）。いずれも長さ 0 のブリッジで
                // つないだポリゴン = `triangulateWithHoles` が穴のために作るのと同じ形
                // なので、ear clipping にそのまま渡せる。
                faces.append(walk)
            }
        }
        return faces
    }

    // MARK: - Segment Intersection

    /// 2 本の線分の交点を、それぞれの線分上の内分比 `(t, u)` として返します。
    /// 共線で重なる場合は重なり区間の両端（最大 2 点）を返します。
    private static func intersections(
        _ pOrigin: SIMD2<Double>, _ pDelta: SIMD2<Double>,
        _ qOrigin: SIMD2<Double>, _ qDelta: SIMD2<Double>,
        tolerance: Double
    ) -> [(t: Double, u: Double)] {
        let pp = dot(pDelta, pDelta)
        let qq = dot(qDelta, qDelta)
        guard pp > 0, qq > 0 else { return [] }
        let pLength = pp.squareRoot()
        let qLength = qq.squareRoot()
        let offset = qOrigin - pOrigin
        let denominator = cross(pDelta, qDelta)

        // 外積は長さの積に比例するので、平行判定は正規化してから行う。
        if abs(denominator) > 1e-12 * pLength * qLength {
            let t = cross(offset, qDelta) / denominator
            let u = cross(offset, pDelta) / denominator
            let tTolerance = tolerance / pLength
            let uTolerance = tolerance / qLength
            guard t >= -tTolerance, t <= 1 + tTolerance,
                  u >= -uTolerance, u <= 1 + uTolerance else { return [] }
            return [(clamped(t), clamped(u))]
        }

        // 平行。直線どうしが離れていれば交差しない。
        guard abs(cross(pDelta, offset)) / pLength <= tolerance else { return [] }

        // 共線。重なり区間の両端を返す。
        let t0 = dot(qOrigin - pOrigin, pDelta) / pp
        let t1 = dot(qOrigin + qDelta - pOrigin, pDelta) / pp
        let overlapLow = Swift.max(0, Swift.min(t0, t1))
        let overlapHigh = Swift.min(1, Swift.max(t0, t1))
        guard overlapHigh >= overlapLow - tolerance / pLength else { return [] }

        func parameterOnQ(_ t: Double) -> Double {
            clamped(dot(pOrigin + pDelta * t - qOrigin, qDelta) / qq)
        }
        var result = [(t: clamped(overlapLow), u: parameterOnQ(overlapLow))]
        if overlapHigh > overlapLow {
            result.append((t: clamped(overlapHigh), u: parameterOnQ(overlapHigh)))
        }
        return result
    }

    // MARK: - Node Table

    /// 座標が一致する点を 1 つのノードにまとめる表。
    ///
    /// 同じ交点でも辺ごとに別々の式から求まるので、丸めで僅かにずれた点を同一視しないと
    /// 面がつながらず抽出が壊れます。格子ハッシュで近傍だけを見て O(1) に近づけています。
    private struct NodeTable {
        private struct Cell: Hashable {
            var x: Int
            var y: Int
        }

        private let origin: SIMD2<Double>
        private let tolerance: Double
        private let cellSize: Double
        private var buckets: [Cell: [Int]] = [:]

        private(set) var points: [SIMD2<Double>] = []
        private(set) var origins: [EarClipTriangulator.VertexOrigin] = []

        init(origin: SIMD2<Double>, tolerance: Double) {
            self.origin = origin
            self.tolerance = tolerance
            self.cellSize = tolerance * 2
        }

        private func cell(_ p: SIMD2<Double>) -> Cell {
            Cell(
                x: Int(((p.x - origin.x) / cellSize).rounded(.down)),
                y: Int(((p.y - origin.y) / cellSize).rounded(.down))
            )
        }

        /// 既存ノードが許容誤差内にあればそのインデックスを、無ければ追加して新しいインデックスを返します。
        mutating func insert(_ p: SIMD2<Double>, origin vertexOrigin: EarClipTriangulator.VertexOrigin) -> Int {
            let base = cell(p)
            for dx in -1...1 {
                for dy in -1...1 {
                    guard let bucket = buckets[Cell(x: base.x + dx, y: base.y + dy)] else { continue }
                    for index in bucket where isNear(points[index], p, tolerance) {
                        return index
                    }
                }
            }
            points.append(p)
            origins.append(vertexOrigin)
            buckets[base, default: []].append(points.count - 1)
            return points.count - 1
        }
    }

    /// 無向辺（両端のノードインデックスを小さい順に持つ）。
    private struct UndirectedEdge: Hashable {
        let a: Int
        let b: Int

        init(_ x: Int, _ y: Int) {
            a = Swift.min(x, y)
            b = Swift.max(x, y)
        }
    }

    // MARK: - Math Helpers

    private static func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        a.x * b.y - a.y * b.x
    }

    private static func dot(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        a.x * b.x + a.y * b.y
    }

    private static func clamped(_ t: Double) -> Double {
        Swift.min(Swift.max(t, 0), 1)
    }

    private static func signedArea(_ loop: [Int], _ points: [SIMD2<Double>]) -> Double {
        var area: Double = 0
        for i in 0..<loop.count {
            let a = points[loop[i]]
            let b = points[loop[(i + 1) % loop.count]]
            area += a.x * b.y - b.x * a.y
        }
        return area * 0.5
    }
}

/// 2 点が許容誤差内で一致するか。
private func isNear(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ tolerance: Double) -> Bool {
    let d = a - b
    return d.x * d.x + d.y * d.y <= tolerance * tolerance
}
