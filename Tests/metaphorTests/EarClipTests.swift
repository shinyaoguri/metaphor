import Testing
@testable import metaphor
@testable import MetaphorCore

// MARK: - Basic Triangulation

@Suite("EarClip Triangulation")
struct EarClipTriangulationTests {

    @Test("triangle produces 3 indices")
    func triangle() {
        let polygon: [(Float, Float)] = [(0, 0), (1, 0), (0.5, 1)]
        let indices = EarClipTriangulator.triangulate(polygon)
        #expect(indices.count == 3)
        for idx in indices {
            #expect(idx >= 0 && idx < polygon.count)
        }
    }

    @Test("convex quad produces 6 indices")
    func convexQuad() {
        let polygon: [(Float, Float)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
        let indices = EarClipTriangulator.triangulate(polygon)
        #expect(indices.count == 6)
    }

    @Test("convex pentagon produces 9 indices")
    func convexPentagon() {
        let polygon: [(Float, Float)] = [
            (0.5, 0), (1, 0.4), (0.8, 1), (0.2, 1), (0, 0.4)
        ]
        let indices = EarClipTriangulator.triangulate(polygon)
        #expect(indices.count == 9)
    }
}

// MARK: - Concave Polygon

@Suite("EarClip Concave")
struct EarClipConcaveTests {

    @Test("concave arrow (L-shape) produces 12 indices")
    func concaveArrow() {
        let polygon: [(Float, Float)] = [
            (0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)
        ]
        let indices = EarClipTriangulator.triangulate(polygon)
        #expect(indices.count == 12)
        for idx in indices {
            #expect(idx >= 0 && idx < polygon.count)
        }
    }

    @Test("concave star (8 vertices) produces 18 indices")
    func concaveStar() {
        let polygon: [(Float, Float)] = [
            (0.5, 0), (0.6, 0.35), (1, 0.35),
            (0.7, 0.55), (0.8, 0.9),
            (0.5, 0.7), (0.2, 0.9), (0.3, 0.55)
        ]
        let indices = EarClipTriangulator.triangulate(polygon)
        #expect(indices.count == 18)
    }
}

// MARK: - Winding Order

/// テスト用ヘルパー: 三角形の面積。
private func triangleArea(
    _ a: (Float, Float), _ b: (Float, Float), _ c: (Float, Float)
) -> Float {
    abs((b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0)) * 0.5
}

/// テスト用ヘルパー: インデックスが指す全三角形の合計面積。
private func totalTriangleArea(_ verts: [(Float, Float)], _ indices: [Int]) -> Float {
    var total: Float = 0
    for i in stride(from: 0, to: indices.count, by: 3) {
        total += triangleArea(verts[indices[i]], verts[indices[i + 1]], verts[indices[i + 2]])
    }
    return total
}

/// テスト用ヘルパー: 点がポリゴン内部にあるか（レイキャスティング）。
private func pointInPolygon(_ p: (Float, Float), _ poly: [(Float, Float)]) -> Bool {
    var inside = false
    let n = poly.count
    var j = n - 1
    for i in 0..<n {
        let a = poly[i]
        let b = poly[j]
        if (a.1 > p.1) != (b.1 > p.1),
           p.0 < (b.0 - a.0) * (p.1 - a.1) / (b.1 - a.1) + a.0 {
            inside.toggle()
        }
        j = i
    }
    return inside
}

/// テスト用ヘルパー: 全三角形の重心がポリゴン内部にあるか検証。
private func allCentroidsInside(_ verts: [(Float, Float)], _ indices: [Int], polygon: [(Float, Float)]) -> Bool {
    for i in stride(from: 0, to: indices.count, by: 3) {
        let a = verts[indices[i]]
        let b = verts[indices[i + 1]]
        let c = verts[indices[i + 2]]
        let centroid = ((a.0 + b.0 + c.0) / 3, (a.1 + b.1 + c.1) / 3)
        if !pointInPolygon(centroid, polygon) {
            return false
        }
    }
    return true
}

@Suite("EarClip Winding")
struct EarClipWindingTests {

    @Test("CW input is handled correctly")
    func clockwiseInput() {
        let ccw: [(Float, Float)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
        let cw: [(Float, Float)] = [(0, 0), (0, 1), (1, 1), (1, 0)]
        let indicesCCW = EarClipTriangulator.triangulate(ccw)
        let indicesCW = EarClipTriangulator.triangulate(cw)
        #expect(indicesCCW.count == 6)
        #expect(indicesCW.count == 6)
    }

    @Test("CW concave L-shape triangles stay inside polygon")
    func clockwiseConcaveLShape() {
        // CCW の L 字を反転した CW 入力。鏡映バグがあると三角形がポリゴン外にはみ出す。
        let cw: [(Float, Float)] = [
            (0, 2), (1, 2), (1, 1), (2, 1), (2, 0), (0, 0)
        ]
        let indices = EarClipTriangulator.triangulate(cw)
        #expect(indices.count == 12)
        #expect(allCentroidsInside(cw, indices, polygon: cw))
        let expectedArea: Float = 3.0
        #expect(abs(totalTriangleArea(cw, indices) - expectedArea) < 1e-4)
    }

    @Test("CW concave star triangles stay inside polygon")
    func clockwiseConcaveStar() {
        let ccw: [(Float, Float)] = [
            (0.5, 0), (0.6, 0.35), (1, 0.35),
            (0.7, 0.55), (0.8, 0.9),
            (0.5, 0.7), (0.2, 0.9), (0.3, 0.55)
        ]
        let cw = Array(ccw.reversed())
        let indices = EarClipTriangulator.triangulate(cw)
        #expect(indices.count == 18)
        #expect(allCentroidsInside(cw, indices, polygon: cw))
    }

    @Test("CCW and CW inputs produce equivalent fills")
    func windingEquivalence() {
        let ccw: [(Float, Float)] = [
            (0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)
        ]
        let cw = Array(ccw.reversed())
        let indicesCCW = EarClipTriangulator.triangulate(ccw)
        let indicesCW = EarClipTriangulator.triangulate(cw)
        #expect(indicesCCW.count == indicesCW.count)
        #expect(allCentroidsInside(ccw, indicesCCW, polygon: ccw))
        #expect(allCentroidsInside(cw, indicesCW, polygon: cw))
        let areaCCW = totalTriangleArea(ccw, indicesCCW)
        let areaCW = totalTriangleArea(cw, indicesCW)
        #expect(abs(areaCCW - areaCW) < 1e-4)
    }
}

// MARK: - Edge Cases

@Suite("EarClip Edge Cases")
struct EarClipEdgeCaseTests {

    @Test("two vertices returns empty")
    func twoVertices() {
        let polygon: [(Float, Float)] = [(0, 0), (1, 1)]
        let indices = EarClipTriangulator.triangulate(polygon)
        #expect(indices.count == 0)
    }

    @Test("empty polygon returns empty")
    func emptyPolygon() {
        let indices = EarClipTriangulator.triangulate([])
        #expect(indices.count == 0)
    }

    @Test("collinear points does not crash")
    func collinearPoints() {
        let polygon: [(Float, Float)] = [(0, 0), (1, 0), (2, 0)]
        let indices = EarClipTriangulator.triangulate(polygon)
        // 3頂点は退化三角形として1つの三角形（3インデックス）を返す（クラッシュしない）。
        #expect(indices.count == 3)
    }
}

// MARK: - Holes

@Suite("EarClip Holes")
struct EarClipHoleTests {

    @Test("hole in square")
    func holeInSquare() {
        let outer: [(Float, Float)] = [(0, 0), (10, 0), (10, 10), (0, 10)]
        let hole: [(Float, Float)] = [(3, 3), (7, 3), (7, 7), (3, 7)]
        let (merged, indices) = EarClipTriangulator.triangulateWithHoles(
            outer: outer, holes: [hole]
        )
        #expect(merged.count > 8)
        #expect(indices.count > 0)
        #expect(indices.count % 3 == 0)
    }

    @Test("multiple holes")
    func multipleHoles() {
        let outer: [(Float, Float)] = [(0, 0), (20, 0), (20, 10), (0, 10)]
        let hole1: [(Float, Float)] = [(2, 2), (5, 2), (5, 5), (2, 5)]
        let hole2: [(Float, Float)] = [(8, 2), (11, 2), (11, 5), (8, 5)]
        let (merged, indices) = EarClipTriangulator.triangulateWithHoles(
            outer: outer, holes: [hole1, hole2]
        )
        #expect(merged.count > 12)
        #expect(indices.count > 0)
        #expect(indices.count % 3 == 0)
    }

    @Test("hole in concave U-shape outer stays inside")
    func holeInConcaveOuter() {
        // 右側が開いた U 字の左腕に穴。ブリッジが外周と交差すると
        // 三角形が切り欠き部分（ポリゴン外）にはみ出す。
        let outer: [(Float, Float)] = [
            (0, 0), (10, 0), (10, 3), (3, 3), (3, 7), (10, 7), (10, 10), (0, 10)
        ]
        let hole: [(Float, Float)] = [(1, 4), (2, 4), (2, 6), (1, 6)]
        let (merged, indices) = EarClipTriangulator.triangulateWithHoles(
            outer: outer, holes: [hole]
        )
        #expect(indices.count % 3 == 0)
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = merged[indices[i]]
            let b = merged[indices[i + 1]]
            let c = merged[indices[i + 2]]
            let centroid = ((a.0 + b.0 + c.0) / 3, (a.1 + b.1 + c.1) / 3)
            #expect(pointInPolygon(centroid, outer))
            #expect(!pointInPolygon(centroid, hole))
        }
        let expectedArea: Float = 72 - 2  // U 字の面積 − 穴の面積
        #expect(abs(totalTriangleArea(merged, indices) - expectedArea) < 1e-3)
    }

    @Test("no holes")
    func noHoles() {
        let outer: [(Float, Float)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
        let (merged, indices) = EarClipTriangulator.triangulateWithHoles(
            outer: outer, holes: []
        )
        #expect(merged.count == 4)
        #expect(indices.count == 6)
    }
}

// MARK: - Helper Functions

@Suite("EarClip Helpers")
struct EarClipHelperTests {

    @Test("signedArea CCW positive, CW negative")
    func signedArea() {
        let ccw: [(Float, Float)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
        let areaCCW = EarClipTriangulator.signedArea(ccw)
        #expect(areaCCW > 0)

        let cw: [(Float, Float)] = [(0, 0), (0, 1), (1, 1), (1, 0)]
        let areaCW = EarClipTriangulator.signedArea(cw)
        #expect(areaCW < 0)
    }

    @Test("pointInTriangle inside and outside")
    func pointInTriangle() {
        let a: (Float, Float) = (0, 0)
        let b: (Float, Float) = (4, 0)
        let c: (Float, Float) = (2, 3)
        #expect(EarClipTriangulator.pointInTriangle((2, 1), a, b, c) == true)
        #expect(EarClipTriangulator.pointInTriangle((5, 5), a, b, c) == false)
        #expect(EarClipTriangulator.pointInTriangle((-1, -1), a, b, c) == false)
    }
}

// MARK: - Stress Test

@Suite("EarClip Stress")
struct EarClipStressTests {

    @Test("20-vertex circular polygon")
    func largerPolygon() {
        var polygon: [(Float, Float)] = []
        let n = 20
        for i in 0..<n {
            let angle = Float(i) / Float(n) * Float.pi * 2
            polygon.append((cos(angle), sin(angle)))
        }
        let indices = EarClipTriangulator.triangulate(polygon)
        #expect(indices.count == (n - 2) * 3)
    }
}
