/// Tessellate 2D polygons using the ear clipping algorithm.
///
/// Supports concave polygons and holes (contours).
/// Runs in O(n^2), which is fast enough for creative coding polygons
/// that typically have fewer than 100 vertices.
enum EarClipTriangulator {

    // MARK: - Public API

    /// Triangulate a simple polygon into triangles.
    /// - Parameter polygon: An array of vertices (at least 3).
    /// - Returns: An array of triangle indices referencing the original vertex array, in groups of 3.
    static func triangulate(_ polygon: [(Float, Float)]) -> [Int] {
        guard polygon.count >= 3 else { return [] }

        var verts = polygon
        ensureCCW(&verts)

        // Build an index list managed like a linked list
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
                    // When no ear is found due to self-intersection, fall back to fan tessellation
                    for i in 1..<(n - 1) {
                        result.append(indices[0])
                        result.append(indices[i])
                        result.append(indices[i + 1])
                    }
                    break
                }
            }
        }

        // Last triangle
        if n == 3 {
            result.append(indices[0])
            result.append(indices[1])
            result.append(indices[2])
        }

        return result
    }

    /// Triangulate a polygon with holes.
    /// - Parameters:
    ///   - outer: The outer boundary vertices.
    ///   - holes: An array of hole vertex arrays.
    /// - Returns: A tuple of the merged vertex array and the triangle index array.
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

    /// Compute the signed area of a polygon (positive = CCW, negative = CW).
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

    /// Determine whether a point lies inside a triangle (excluding the boundary).
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

    /// Ensure counter-clockwise winding order; reverse if clockwise.
    private static func ensureCCW(_ polygon: inout [(Float, Float)]) {
        if signedArea(polygon) < 0 {
            polygon.reverse()
        }
    }

    /// Compute the 2D cross product (sign indicates rotation direction).
    private static func cross2D(
        _ p: (Float, Float),
        _ a: (Float, Float),
        _ b: (Float, Float)
    ) -> Float {
        (a.0 - p.0) * (b.1 - p.1) - (a.1 - p.1) * (b.0 - p.0)
    }

    /// Determine whether a vertex is convex (left turn in a CCW polygon).
    private static func isConvex(
        _ prev: (Float, Float),
        _ curr: (Float, Float),
        _ next: (Float, Float)
    ) -> Bool {
        cross2D(prev, curr, next) > 0
    }

    /// Determine whether a vertex is an "ear" that can be clipped.
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

        // Not an ear if the vertex is reflex (not convex)
        guard isConvex(a, b, c) else { return false }

        // Check that no other vertex lies inside triangle ABC
        for i in 0..<count {
            let idx = allIndices[i]
            if idx == prev || idx == curr || idx == next { continue }

            let p = verts[idx]
            // Skip vertices that coincide with a triangle vertex
            if (p.0 == a.0 && p.1 == a.1) ||
               (p.0 == b.0 && p.1 == b.1) ||
               (p.0 == c.0 && p.1 == c.1) { continue }

            if pointInTriangle(p, a, b, c) {
                return false
            }
        }

        return true
    }

    /// Merge holes into the outer boundary using bridge edges.
    ///
    /// For each hole, find the rightmost vertex and search for a visible edge
    /// on the outer boundary. Insert a bridge (two duplicate vertices) to
    /// combine everything into a single polygon.
    private static func mergeHoles(
        outer: [(Float, Float)],
        holes: [[(Float, Float)]]
    ) -> [(Float, Float)] {
        var result = outer
        ensureCCW(&result)

        // Normalize holes to CW order and sort by rightmost vertex X coordinate
        struct HoleInfo {
            var vertices: [(Float, Float)]
            var rightmostIndex: Int
            var rightmostX: Float
        }

        var holeInfos: [HoleInfo] = holes.compactMap { hole in
            guard hole.count >= 3 else { return nil }
            var h = hole
            // Holes must be in CW order
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

        // Process holes from right to left (largest X first)
        holeInfos.sort { $0.rightmostX > $1.rightmostX }

        for holeInfo in holeInfos {
            let holePoint = holeInfo.vertices[holeInfo.rightmostIndex]

            // Find the nearest visible edge endpoint on the outer boundary
            var bestIdx = 0
            var bestDist: Float = .infinity

            for i in 0..<result.count {
                let a = result[i]

                // Cast a horizontal ray rightward from holePoint to find the nearest visible vertex
                if a.0 >= holePoint.0 {
                    let dist = (a.0 - holePoint.0) * (a.0 - holePoint.0) + (a.1 - holePoint.1) * (a.1 - holePoint.1)
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = i
                    }
                }
            }

            // If no visible point is found (rare case where hole is to the right of outer), use nearest point
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

            // Insert bridge: add hole vertices after bestIdx in the outer boundary
            // Reorder hole vertices starting from rightmostIndex
            let n = holeInfo.vertices.count
            var reorderedHole: [(Float, Float)] = []
            reorderedHole.reserveCapacity(n)
            for i in 0..<n {
                reorderedHole.append(holeInfo.vertices[(holeInfo.rightmostIndex + i) % n])
            }

            // Insert: [... outer[bestIdx], hole[0], hole[1], ..., hole[n-1], hole[0], outer[bestIdx], ...]
            var merged: [(Float, Float)] = []
            merged.reserveCapacity(result.count + reorderedHole.count + 2)
            for i in 0...bestIdx {
                merged.append(result[i])
            }
            for v in reorderedHole {
                merged.append(v)
            }
            // Bridge back: duplicate the hole start point and the outer connection point
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
