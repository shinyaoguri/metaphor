import XCTest
@testable import metaphor

final class EarClipTests: XCTestCase {

    // MARK: - Basic Triangulation

    func testTriangle() {
        // 3頂点 → 1三角形
        let polygon: [(Float, Float)] = [(0, 0), (1, 0), (0.5, 1)]
        let indices = EarClipTriangulator.triangulate(polygon)
        XCTAssertEqual(indices.count, 3, "三角形は3インデックス")
        // インデックスが有効な範囲内か
        for idx in indices {
            XCTAssertTrue(idx >= 0 && idx < polygon.count)
        }
    }

    func testConvexQuad() {
        // 凸四角形 → 2三角形
        let polygon: [(Float, Float)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
        let indices = EarClipTriangulator.triangulate(polygon)
        XCTAssertEqual(indices.count, 6, "四角形は6インデックス（2三角形）")
    }

    func testConvexPentagon() {
        // 凸五角形 → 3三角形
        let polygon: [(Float, Float)] = [
            (0.5, 0), (1, 0.4), (0.8, 1), (0.2, 1), (0, 0.4)
        ]
        let indices = EarClipTriangulator.triangulate(polygon)
        XCTAssertEqual(indices.count, 9, "五角形は9インデックス（3三角形）")
    }

    // MARK: - Concave Polygon

    func testConcaveArrow() {
        // 矢印型の凹多角形（L字型）
        let polygon: [(Float, Float)] = [
            (0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)
        ]
        let indices = EarClipTriangulator.triangulate(polygon)
        XCTAssertEqual(indices.count, 12, "6頂点は12インデックス（4三角形）")
        // すべてのインデックスが有効
        for idx in indices {
            XCTAssertTrue(idx >= 0 && idx < polygon.count)
        }
    }

    func testConcaveStar() {
        // 凹の星型（8頂点）
        let polygon: [(Float, Float)] = [
            (0.5, 0), (0.6, 0.35), (1, 0.35),
            (0.7, 0.55), (0.8, 0.9),
            (0.5, 0.7), (0.2, 0.9), (0.3, 0.55)
        ]
        let indices = EarClipTriangulator.triangulate(polygon)
        XCTAssertEqual(indices.count, 18, "8頂点は18インデックス（6三角形）")
    }

    // MARK: - Winding Order

    func testClockwiseInput() {
        // CW入力は自動的にCCWに正規化される
        let ccw: [(Float, Float)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
        let cw: [(Float, Float)] = [(0, 0), (0, 1), (1, 1), (1, 0)]

        let indicesCCW = EarClipTriangulator.triangulate(ccw)
        let indicesCW = EarClipTriangulator.triangulate(cw)

        // 両方とも有効な三角形分割を返す
        XCTAssertEqual(indicesCCW.count, 6)
        XCTAssertEqual(indicesCW.count, 6)
    }

    // MARK: - Edge Cases

    func testTwoVertices() {
        let polygon: [(Float, Float)] = [(0, 0), (1, 1)]
        let indices = EarClipTriangulator.triangulate(polygon)
        XCTAssertEqual(indices.count, 0, "2頂点以下は空")
    }

    func testEmptyPolygon() {
        let indices = EarClipTriangulator.triangulate([])
        XCTAssertEqual(indices.count, 0, "空多角形は空")
    }

    func testCollinearPoints() {
        // 同一直線上の3点
        let polygon: [(Float, Float)] = [(0, 0), (1, 0), (2, 0)]
        let indices = EarClipTriangulator.triangulate(polygon)
        // 退化三角形を生成する場合もあるが、クラッシュしない
        XCTAssertTrue(indices.count >= 0)
    }

    // MARK: - Holes

    func testHoleInSquare() {
        let outer: [(Float, Float)] = [(0, 0), (10, 0), (10, 10), (0, 10)]
        let hole: [(Float, Float)] = [(3, 3), (7, 3), (7, 7), (3, 7)]
        let (merged, indices) = EarClipTriangulator.triangulateWithHoles(
            outer: outer, holes: [hole]
        )
        // 統合後の頂点数 = 4(外周) + 4(穴) + 2(ブリッジ重複)
        XCTAssertGreaterThan(merged.count, 8)
        // 三角形が生成される
        XCTAssertGreaterThan(indices.count, 0)
        XCTAssertTrue(indices.count % 3 == 0, "インデックスは3の倍数")
    }

    func testMultipleHoles() {
        let outer: [(Float, Float)] = [(0, 0), (20, 0), (20, 10), (0, 10)]
        let hole1: [(Float, Float)] = [(2, 2), (5, 2), (5, 5), (2, 5)]
        let hole2: [(Float, Float)] = [(8, 2), (11, 2), (11, 5), (8, 5)]

        let (merged, indices) = EarClipTriangulator.triangulateWithHoles(
            outer: outer, holes: [hole1, hole2]
        )
        XCTAssertGreaterThan(merged.count, 12)
        XCTAssertGreaterThan(indices.count, 0)
        XCTAssertTrue(indices.count % 3 == 0)
    }

    func testNoHoles() {
        let outer: [(Float, Float)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
        let (merged, indices) = EarClipTriangulator.triangulateWithHoles(
            outer: outer, holes: []
        )
        XCTAssertEqual(merged.count, 4)
        XCTAssertEqual(indices.count, 6)
    }

    // MARK: - Helper Functions

    func testSignedArea() {
        // CCW四角形は正の面積
        let ccw: [(Float, Float)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
        let areaCCW = EarClipTriangulator.signedArea(ccw)
        XCTAssertGreaterThan(areaCCW, 0, "CCW多角形は正の面積")

        // CW四角形は負の面積
        let cw: [(Float, Float)] = [(0, 0), (0, 1), (1, 1), (1, 0)]
        let areaCW = EarClipTriangulator.signedArea(cw)
        XCTAssertLessThan(areaCW, 0, "CW多角形は負の面積")
    }

    func testPointInTriangle() {
        let a: (Float, Float) = (0, 0)
        let b: (Float, Float) = (4, 0)
        let c: (Float, Float) = (2, 3)

        // 内部の点
        XCTAssertTrue(EarClipTriangulator.pointInTriangle((2, 1), a, b, c))
        // 外部の点
        XCTAssertFalse(EarClipTriangulator.pointInTriangle((5, 5), a, b, c))
        // 明らかに外側
        XCTAssertFalse(EarClipTriangulator.pointInTriangle((-1, -1), a, b, c))
    }

    // MARK: - Stress Test

    func testLargerPolygon() {
        // 20頂点の円形多角形
        var polygon: [(Float, Float)] = []
        let n = 20
        for i in 0..<n {
            let angle = Float(i) / Float(n) * Float.pi * 2
            polygon.append((cos(angle), sin(angle)))
        }
        let indices = EarClipTriangulator.triangulate(polygon)
        XCTAssertEqual(indices.count, (n - 2) * 3, "\(n)頂点は\((n - 2) * 3)インデックス")
    }
}
