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
        #expect(indices.count >= 0)
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
