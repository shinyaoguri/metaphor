/// イアクリッピングアルゴリズムを使用して2Dポリゴンをテッセレーションします。
///
/// 凹多角形と穴（コンター）をサポートします。
/// 計算量は O(n^2) で、一般的に100頂点未満のクリエイティブコーディング用
/// ポリゴンには十分高速です。
enum EarClipTriangulator {

    // MARK: - Public API

    /// 単純なポリゴンを三角形にテッセレーションします。
    /// - Parameter polygon: 頂点の配列（最低3つ）。
    /// - Returns: 元の頂点配列を参照する三角形インデックスの配列（3つずつのグループ）。
    static func triangulate(_ polygon: [(Float, Float)]) -> [Int] {
        guard polygon.count >= 3 else { return [] }

        var verts = polygon
        ensureCCW(&verts)

        // 連結リストのように管理するインデックスリストを構築
        var indices = Array(0..<verts.count)
        var result: [Int] = []
        result.reserveCapacity((verts.count - 2) * 3)

        var failCount = 0
        var n = indices.count

        while n > 3 {
            var earFound = false
            for i in 0..<n {
                let prev = (i + n - 1) % n
                let next = (i + 1) % n

                if isEar(verts, indices, prev: indices[prev], curr: indices[i], next: indices[next], allIndices: indices, count: n) {
                    result.append(indices[prev])
                    result.append(indices[i])
                    result.append(indices[next])

                    indices.remove(at: i)
                    n -= 1
                    earFound = true
                    failCount = 0
                    break
                }
            }

            if !earFound {
                failCount += 1
                if failCount > n {
                    // 自己交差により耳が見つからない場合、ファンテッセレーションにフォールバック
                    for i in 1..<(n - 1) {
                        result.append(indices[0])
                        result.append(indices[i])
                        result.append(indices[i + 1])
                    }
                    break
                }
            }
        }

        // 最後の三角形
        if n == 3 {
            result.append(indices[0])
            result.append(indices[1])
            result.append(indices[2])
        }

        return result
    }

    /// 穴付きポリゴンをテッセレーションします。
    /// - Parameters:
    ///   - outer: 外周境界の頂点。
    ///   - holes: 穴の頂点配列の配列。
    /// - Returns: マージされた頂点配列と三角形インデックス配列のタプル。
    static func triangulateWithHoles(
        outer: [(Float, Float)],
        holes: [[(Float, Float)]]
    ) -> (vertices: [(Float, Float)], indices: [Int]) {
        guard outer.count >= 3 else { return (outer, []) }
        guard !holes.isEmpty else {
            return (outer, triangulate(outer))
        }

        let merged = mergeHoles(outer: outer, holes: holes)
        let indices = triangulate(merged)
        return (merged, indices)
    }

    // MARK: - Geometry Helpers

    /// ポリゴンの符号付き面積を計算します（正 = CCW、負 = CW）。
    static func signedArea(_ verts: [(Float, Float)]) -> Float {
        var area: Float = 0
        let n = verts.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += verts[i].0 * verts[j].1
            area -= verts[j].0 * verts[i].1
        }
        return area * 0.5
    }

    /// 点が三角形の内部にあるかどうかを判定します（境界を除く）。
    static func pointInTriangle(
        _ p: (Float, Float),
        _ a: (Float, Float), _ b: (Float, Float), _ c: (Float, Float)
    ) -> Bool {
        let d1 = cross2D(p, a, b)
        let d2 = cross2D(p, b, c)
        let d3 = cross2D(p, c, a)

        let hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0)
        let hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0)

        return !(hasNeg && hasPos)
    }

    // MARK: - Private Helpers

    /// 反時計回りのワインディングオーダーを保証し、時計回りの場合は反転します。
    private static func ensureCCW(_ polygon: inout [(Float, Float)]) {
        if signedArea(polygon) < 0 {
            polygon.reverse()
        }
    }

    /// 2D外積を計算します（符号は回転方向を示します）。
    private static func cross2D(
        _ p: (Float, Float),
        _ a: (Float, Float),
        _ b: (Float, Float)
    ) -> Float {
        (a.0 - p.0) * (b.1 - p.1) - (a.1 - p.1) * (b.0 - p.0)
    }

    /// 頂点が凸かどうかを判定します（CCWポリゴンでの左折）。
    private static func isConvex(
        _ prev: (Float, Float),
        _ curr: (Float, Float),
        _ next: (Float, Float)
    ) -> Bool {
        cross2D(prev, curr, next) > 0
    }

    /// 頂点がクリップ可能な「耳」かどうかを判定します。
    private static func isEar(
        _ verts: [(Float, Float)],
        _ indices: [Int],
        prev: Int, curr: Int, next: Int,
        allIndices: [Int],
        count: Int
    ) -> Bool {
        let a = verts[prev]
        let b = verts[curr]
        let c = verts[next]

        // 頂点が凹（非凸）の場合は耳ではない
        guard isConvex(a, b, c) else { return false }

        // 他の頂点が三角形 ABC の内部にないことを確認
        for i in 0..<count {
            let idx = allIndices[i]
            if idx == prev || idx == curr || idx == next { continue }

            let p = verts[idx]
            // 三角形の頂点と一致する頂点はスキップ
            if (p.0 == a.0 && p.1 == a.1) ||
               (p.0 == b.0 && p.1 == b.1) ||
               (p.0 == c.0 && p.1 == c.1) { continue }

            if pointInTriangle(p, a, b, c) {
                return false
            }
        }

        return true
    }

    /// ブリッジエッジを使用して穴を外周境界にマージします。
    ///
    /// 各穴について最右の頂点を見つけ、外周境界上の可視エッジを検索します。
    /// ブリッジ（2つの重複頂点）を挿入して、すべてを単一ポリゴンに結合します。
    private static func mergeHoles(
        outer: [(Float, Float)],
        holes: [[(Float, Float)]]
    ) -> [(Float, Float)] {
        var result = outer
        ensureCCW(&result)

        // 穴をCW順にノーマライズし、最右頂点のX座標でソート
        struct HoleInfo {
            var vertices: [(Float, Float)]
            var rightmostIndex: Int
            var rightmostX: Float
        }

        var holeInfos: [HoleInfo] = holes.compactMap { hole in
            guard hole.count >= 3 else { return nil }
            var h = hole
            // 穴はCW順でなければならない
            if signedArea(h) > 0 {
                h.reverse()
            }
            var maxIdx = 0
            var maxX = h[0].0
            for i in 1..<h.count {
                if h[i].0 > maxX {
                    maxX = h[i].0
                    maxIdx = i
                }
            }
            return HoleInfo(vertices: h, rightmostIndex: maxIdx, rightmostX: maxX)
        }

        // 穴を右から左へ処理（最大X優先）
        holeInfos.sort { $0.rightmostX > $1.rightmostX }

        for holeInfo in holeInfos {
            let holePoint = holeInfo.vertices[holeInfo.rightmostIndex]

            // 外周境界上の最も近い可視エッジ端点を検索
            var bestIdx = 0
            var bestDist: Float = .infinity

            for i in 0..<result.count {
                let a = result[i]

                // holePoint から右方向に水平レイをキャストし、最も近い可視頂点を検索
                if a.0 >= holePoint.0 {
                    let dist = (a.0 - holePoint.0) * (a.0 - holePoint.0) + (a.1 - holePoint.1) * (a.1 - holePoint.1)
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = i
                    }
                }
            }

            // 可視点が見つからない場合（穴が外周の右側にあるまれなケース）、最近傍点を使用
            if bestDist == .infinity {
                for i in 0..<result.count {
                    let a = result[i]
                    let dist = (a.0 - holePoint.0) * (a.0 - holePoint.0) + (a.1 - holePoint.1) * (a.1 - holePoint.1)
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = i
                    }
                }
            }

            // ブリッジを挿入: 外周境界の bestIdx の後に穴の頂点を追加
            // rightmostIndex から始まるように穴の頂点を並べ替え
            let n = holeInfo.vertices.count
            var reorderedHole: [(Float, Float)] = []
            reorderedHole.reserveCapacity(n)
            for i in 0..<n {
                reorderedHole.append(holeInfo.vertices[(holeInfo.rightmostIndex + i) % n])
            }

            // 挿入: [... outer[bestIdx], hole[0], hole[1], ..., hole[n-1], hole[0], outer[bestIdx], ...]
            var merged: [(Float, Float)] = []
            merged.reserveCapacity(result.count + reorderedHole.count + 2)
            for i in 0...bestIdx {
                merged.append(result[i])
            }
            for v in reorderedHole {
                merged.append(v)
            }
            // ブリッジバック: 穴の開始点と外周の接続点を複製
            merged.append(reorderedHole[0])
            merged.append(result[bestIdx])
            for i in (bestIdx + 1)..<result.count {
                merged.append(result[i])
            }

            result = merged
        }

        return result
    }
}
