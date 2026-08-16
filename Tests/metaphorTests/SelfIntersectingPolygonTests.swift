import Foundation
import MetaphorTestSupport
import Testing
@testable import MetaphorCore

// MARK: - テスト用ヘルパー

/// {5/2} 星型多角形（五芒星）の頂点列。外接円上の 5 点を 2 つ飛ばしで結びます。
private func pentagram(center: (Float, Float), radius: Float) -> [(Float, Float)] {
    (0..<5).map { k in
        let a = -Float.pi / 2 + Float(k) * 4 * Float.pi / 5
        return (center.0 + radius * cos(a), center.1 + radius * sin(a))
    }
}

/// 五芒星の外形（星の輪郭そのもの）を 10 角形として作ります。期待面積の基準に使います。
private func starOutline(center: (Float, Float), radius: Float) -> [(Float, Float)] {
    // 交点までの距離は外接円半径の cos(72°) / cos(36°) 倍。
    let inner = radius * cos(2 * Float.pi / 5) / cos(Float.pi / 5)
    var result: [(Float, Float)] = []
    for k in 0..<5 {
        let outerAngle = -Float.pi / 2 + Float(k) * 2 * Float.pi / 5
        result.append((center.0 + radius * cos(outerAngle), center.1 + radius * sin(outerAngle)))
        let innerAngle = outerAngle + Float.pi / 5
        result.append((center.0 + inner * cos(innerAngle), center.1 + inner * sin(innerAngle)))
    }
    return result
}

/// 極座標で点を作ります（角度は -90° を真上とする度数法）。
private func polar(center: (Float, Float), radius: Float, degrees: Float) -> (Float, Float) {
    let a = (degrees - 90) * Float.pi / 180
    return (center.0 + radius * cos(a), center.1 + radius * sin(a))
}

private func triangleArea(_ a: (Float, Float), _ b: (Float, Float), _ c: (Float, Float)) -> Float {
    abs((b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0)) * 0.5
}

private func polygonArea(_ poly: [(Float, Float)]) -> Float {
    abs(EarClipTriangulator.signedArea(poly))
}

extension EarClipTriangulator.Tessellation {
    /// 三角形群のどれかが点を覆っているか。
    fileprivate func covers(_ p: (Float, Float)) -> Bool {
        for i in stride(from: 0, to: indices.count, by: 3) {
            if EarClipTriangulator.pointInTriangle(
                p, vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]]
            ) {
                return true
            }
        }
        return false
    }

    /// 三角形群の面積合計。面どうしが重なっていなければ塗られた領域の面積と一致します。
    fileprivate var totalArea: Float {
        var total: Float = 0
        for i in stride(from: 0, to: indices.count, by: 3) {
            total += triangleArea(vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]])
        }
        return total
    }

    /// インデックスが頂点配列の範囲に収まっているか。
    fileprivate var isWellFormed: Bool {
        indices.count % 3 == 0
            && indices.allSatisfy { $0 >= 0 && $0 < vertices.count }
            && origins.count == vertices.count
    }
}

// MARK: - 五芒星（Issue #768 の再現）

@Suite("Self-Intersecting Fill: Pentagram")
struct PentagramFillTests {

    private let center: (Float, Float) = (240, 190)
    private let radius: Float = 140

    @Test("五芒星は星の形に塗られる（腕は塗られ、腕と腕のあいだは塗られない）")
    func pentagramFillsAsStar() {
        let tess = EarClipTriangulator.triangulateNonZero(pentagram(center: center, radius: radius))
        #expect(tess.isWellFormed)

        // 5 本の腕の中ほど（外接円の 0.8 倍）は塗られている。
        for k in 0..<5 {
            let armCenter = polar(center: center, radius: radius * 0.8, degrees: Float(k) * 72)
            #expect(tess.covers(armCenter), "腕 \(k) の中ほどが塗られていない")
        }

        // 腕と腕のあいだ（凹んだ切れ込みの外側）は塗られていない。
        // 交点までの距離は 0.382R なので、0.6R は星の外・外接五角形の内側。
        for k in 0..<5 {
            let notch = polar(center: center, radius: radius * 0.6, degrees: Float(k) * 72 + 36)
            #expect(!tess.covers(notch), "腕 \(k) と \(k + 1) のあいだが塗られている")
        }
    }

    @Test("nonzero 規則なので中央の五角形も塗られる（even-odd ではない）")
    func centerIsFilledUnderNonZeroRule() {
        let tess = EarClipTriangulator.triangulateNonZero(pentagram(center: center, radius: radius))
        #expect(tess.covers(center))
        #expect(tess.covers(polar(center: center, radius: radius * 0.2, degrees: 0)))
    }

    @Test("塗られた面積は星の輪郭の面積と一致する（重なりも隙間も無い）")
    func filledAreaMatchesStarOutline() {
        let tess = EarClipTriangulator.triangulateNonZero(pentagram(center: center, radius: radius))
        let expected = polygonArea(starOutline(center: center, radius: radius))
        #expect(abs(tess.totalArea - expected) < expected * 1e-3)
    }

    @Test("巻き方向を反転しても同じ形に塗られる")
    func reversedWindingProducesSameFill() {
        let reversed = Array(pentagram(center: center, radius: radius).reversed())
        let tess = EarClipTriangulator.triangulateNonZero(reversed)
        let expected = polygonArea(starOutline(center: center, radius: radius))
        #expect(abs(tess.totalArea - expected) < expected * 1e-3)
        #expect(tess.covers(center))
        #expect(!tess.covers(polar(center: center, radius: radius * 0.6, degrees: 36)))
    }

    @Test("Issue #768 の頂点列がそのまま星になる")
    func issueVertexListFillsAsStar() {
        // Issue 本文のスケッチと同じ頂点列（480x360）。
        let polygon: [(Float, Float)] = [
            (240, 60), (330, 300), (90, 150), (390, 150), (150, 300)
        ]
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.isWellFormed)
        // 上の腕の先端付近は塗られ、その左右の切れ込みは塗られない。
        #expect(tess.covers((240, 80)))
        #expect(!tess.covers((160, 120)))
        #expect(!tess.covers((320, 120)))
        // 下側の切れ込み（星の凹点は (240, 242) あたり）。ファンで塗ると
        // ここまで平行四辺形が広がる。
        #expect(!tess.covers((240, 265)))
        // 中央は nonzero なので塗られる。
        #expect(tess.covers((240, 180)))
    }
}

// MARK: - 8 の字・リボン

@Suite("Self-Intersecting Fill: Figure Eight")
struct FigureEightFillTests {

    @Test("8 の字は両方のループが塗られ、外側は塗られない")
    func bothLobesAreFilled() {
        // (0,0) → (1,0) → (0,1) → (1,1) → close。中央 (0.5, 0.5) で交差する蝶ネクタイ。
        let polygon: [(Float, Float)] = [(0, 0), (1, 0), (0, 1), (1, 1)]
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.isWellFormed)
        #expect(tess.covers((0.5, 0.2)))   // 下のループ
        #expect(tess.covers((0.5, 0.8)))   // 上のループ
        #expect(!tess.covers((0.15, 0.5)))  // 左の空き
        #expect(!tess.covers((0.85, 0.5)))  // 右の空き
        // 三角形 2 つぶん（それぞれ底辺 1・高さ 0.5）。
        #expect(abs(tess.totalArea - 0.5) < 1e-4)
    }

    @Test("同じ向きに 2 周する輪は 1 周ぶんの面積しか塗らない")
    func doubleWoundRingFillsOnce() {
        // 正方形を 2 周する頂点列。辺が完全に重なるので、巻き数 2 の 1 領域になる。
        let square: [(Float, Float)] = [(0, 0), (10, 0), (10, 10), (0, 10)]
        let tess = EarClipTriangulator.triangulateNonZero(square + square)
        #expect(tess.isWellFormed)
        #expect(tess.covers((5, 5)))
        #expect(!tess.covers((-1, 5)))
        #expect(abs(tess.totalArea - 100) < 1e-2)
    }
}

// MARK: - 退化ケース

@Suite("Self-Intersecting Fill: Degenerate Inputs")
struct SelfIntersectingDegenerateTests {

    @Test("重複頂点を含む五芒星も星になる")
    func duplicatedVerticesAreIgnored() {
        let base = pentagram(center: (0, 0), radius: 100)
        // 連続する重複・先頭と同じ終端の両方を混ぜる。
        var polygon: [(Float, Float)] = []
        for v in base {
            polygon.append(v)
            polygon.append(v)
        }
        polygon.append(base[0])
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.isWellFormed)
        let expected = polygonArea(starOutline(center: (0, 0), radius: 100))
        #expect(abs(tess.totalArea - expected) < expected * 1e-3)
    }

    @Test("共線の 3 点を挟んでも単純多角形として塗られる")
    func collinearVerticesDoNotBreakFill() {
        // 正方形の下辺に中点を足しただけ（自己交差なし）。
        let polygon: [(Float, Float)] = [(0, 0), (5, 0), (10, 0), (10, 10), (0, 10)]
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.isWellFormed)
        #expect(abs(tess.totalArea - 100) < 1e-3)
        #expect(tess.covers((5, 5)))
    }

    @Test("頂点が辺の上に乗る接触交差でも面が分かれる")
    func vertexTouchingEdgeIsResolved() {
        // 正方形の上辺 (0,10)-(10,10) の中点 (5,10) に、下から三角の突起が触れる。
        // 交差はしないが辺の上に頂点が乗る（T 字接触）。
        let polygon: [(Float, Float)] = [
            (0, 0), (10, 0), (10, 10), (5, 10), (7, 14), (3, 14), (5, 10), (0, 10)
        ]
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.isWellFormed)
        #expect(tess.covers((5, 5)))    // 正方形の中
        #expect(tess.covers((5, 12)))   // 突起の中
        #expect(!tess.covers((1, 13)))  // 突起の外
        #expect(abs(tess.totalArea - (100 + 8)) < 1e-2)
    }

    @Test("同じ辺を往復する棘は面積を持たない")
    func degenerateSpikeAddsNoArea() {
        // 正方形の右辺から水平に出て同じ経路で戻る棘。
        let polygon: [(Float, Float)] = [
            (0, 0), (10, 0), (10, 5), (15, 5), (10, 5), (10, 10), (0, 10)
        ]
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.isWellFormed)
        #expect(abs(tess.totalArea - 100) < 1e-2)
        #expect(!tess.covers((13, 5.5)))
    }

    @Test("2 つのループが 1 点だけで接する形は両方塗られる")
    func loopsTouchingAtSinglePointAreBothFilled() {
        let polygon: [(Float, Float)] = [
            (0, 0), (10, 0), (5, 5),   // 下のループ
            (10, 10), (0, 10), (5, 5)  // 上のループ（(5,5) を共有）
        ]
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.isWellFormed)
        #expect(tess.covers((5, 1)))
        #expect(tess.covers((5, 9)))
        #expect(!tess.covers((1, 5)))
        #expect(abs(tess.totalArea - 50) < 1e-2)
    }

    @Test("内側のループが逆巻きなら穴になる（1 点で接する場合も）")
    func nestedReversedLoopBecomesHole() {
        // 外周 CCW の正方形と、その内側の CW の正方形。両者は (0,0) で 1 点だけ接する。
        // 内側の巻き数は 1 - 1 = 0 なので nonzero では抜ける。
        let polygon: [(Float, Float)] = [
            (0, 0), (10, 0), (10, 10), (0, 10),
            (0, 0), (1, 3), (4, 4), (3, 1)
        ]
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.isWellFormed)
        #expect(tess.covers((8, 8)))     // 外周と内側のあいだ
        #expect(!tess.covers((2.5, 2.5)))  // 内側（抜ける）
        #expect(abs(tess.totalArea - (100 - 8)) < 1e-2)
    }

    @Test("内側のループが同じ巻きなら重ならずに 1 回だけ塗られる")
    func nestedSameWindingLoopIsFilledOnce() {
        // 上と同じ形で内側だけ CCW。巻き数 2 なので塗られるが、面積は外周ぶんだけ。
        let polygon: [(Float, Float)] = [
            (0, 0), (10, 0), (10, 10), (0, 10),
            (0, 0), (3, 1), (4, 4), (1, 3)
        ]
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.isWellFormed)
        #expect(tess.covers((8, 8)))
        #expect(tess.covers((2.5, 2.5)))
        #expect(abs(tess.totalArea - 100) < 1e-2)
    }

    @Test("全点が共線・頂点数不足でもクラッシュしない")
    func degenerateInputsReturnEmpty() {
        #expect(EarClipTriangulator.triangulateNonZero([]).indices.isEmpty)
        #expect(EarClipTriangulator.triangulateNonZero([(0, 0), (1, 1)]).indices.isEmpty)

        let collinear: [(Float, Float)] = [(0, 0), (1, 0), (2, 0), (3, 0)]
        let tess = EarClipTriangulator.triangulateNonZero(collinear)
        #expect(tess.isWellFormed)
        #expect(tess.totalArea < 1e-5)

        let allSame: [(Float, Float)] = [(2, 2), (2, 2), (2, 2), (2, 2)]
        #expect(EarClipTriangulator.triangulateNonZero(allSame).totalArea < 1e-5)
    }
}

// MARK: - 既存の単純多角形が退行していないこと

@Suite("Self-Intersecting Fill: Simple Polygons Unchanged")
struct SimplePolygonRegressionTests {

    @Test("自己交差が無ければ triangulate と同じ結果を返す", arguments: [
        [(0, 0), (1, 0), (0.5, 1)] as [(Float, Float)],
        [(0, 0), (1, 0), (1, 1), (0, 1)] as [(Float, Float)],
        [(0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)] as [(Float, Float)],
        [(0, 2), (1, 2), (1, 1), (2, 1), (2, 0), (0, 0)] as [(Float, Float)],
        [
            (0.5, 0), (0.6, 0.35), (1, 0.35),
            (0.7, 0.55), (0.8, 0.9),
            (0.5, 0.7), (0.2, 0.9), (0.3, 0.55)
        ] as [(Float, Float)]
    ])
    func matchesPlainTriangulation(polygon: [(Float, Float)]) {
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.indices == EarClipTriangulator.triangulate(polygon))
        #expect(tess.vertices.count == polygon.count)
        for (i, v) in tess.vertices.enumerated() {
            #expect(v.0 == polygon[i].0 && v.1 == polygon[i].1)
        }
        #expect(tess.origins.allSatisfy { $0.from == $0.to && $0.t == 0 })
    }

    @Test("20 角形の円もそのまま扱える")
    func circleIsUnchanged() {
        var polygon: [(Float, Float)] = []
        for i in 0..<20 {
            let angle = Float(i) / 20 * Float.pi * 2
            polygon.append((cos(angle), sin(angle)))
        }
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.indices.count == 18 * 3)
        #expect(tess.indices == EarClipTriangulator.triangulate(polygon))
    }
}

// MARK: - 実際に描いた絵

/// テッセレーションだけでなく、`beginShape()` / `polygon()` の塗り経路が
/// 差し替わっていることをピクセルで確かめます。
@Suite("Self-Intersecting Fill: Rendered", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct SelfIntersectingRenderTests {

    private static let size = 128
    private static let center: (Float, Float) = (64, 64)
    private static let radius: Float = 52

    private func isLit(_ image: GoldenImage, _ p: (Float, Float)) -> Bool {
        let x = Int(p.0.rounded())
        let y = Int(p.1.rounded())
        let i = (y * image.width + x) * 4
        return Int(image.rgba[i]) > 128
    }

    private func renderPentagram(
        _ draw: @escaping @MainActor (SketchContext, [(Float, Float)]) -> Void
    ) throws -> GoldenImage {
        let vertices = pentagram(center: Self.center, radius: Self.radius)
        return try OffscreenSketchHarness.render(size: Self.size) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noStroke()
            ctx.fill(Color(r: 1, g: 1, b: 1))
            draw(ctx, vertices)
        }
    }

    private func expectStar(_ image: GoldenImage) {
        for k in 0..<5 {
            let arm = polar(center: Self.center, radius: Self.radius * 0.8, degrees: Float(k) * 72)
            #expect(isLit(image, arm), "腕 \(k) が塗られていない")
            let notch = polar(center: Self.center, radius: Self.radius * 0.6, degrees: Float(k) * 72 + 36)
            #expect(!isLit(image, notch), "腕 \(k) と \(k + 1) のあいだが塗られている")
        }
        #expect(isLit(image, Self.center), "中央（巻き数 2）が塗られていない")
    }

    @Test("beginShape() の五芒星が星に描かれる")
    func beginShapeDrawsStar() throws {
        let image = try renderPentagram { ctx, vertices in
            ctx.beginShape()
            for v in vertices { ctx.vertex(v.0, v.1) }
            ctx.endShape(.close)
        }
        expectStar(image)
    }

    @Test("polygon() の五芒星が星に描かれる")
    func polygonDrawsStar() throws {
        let image = try renderPentagram { ctx, vertices in
            ctx.polygon(vertices)
        }
        expectStar(image)
    }
}

// MARK: - 頂点属性の補間に使う由来情報

@Suite("Self-Intersecting Fill: Vertex Origins")
struct VertexOriginTests {

    @Test("交点の由来は元の辺と内分比を指す")
    func intersectionOriginsPointAtSourceEdge() {
        let polygon: [(Float, Float)] = [(0, 0), (1, 0), (0, 1), (1, 1)]
        let tess = EarClipTriangulator.triangulateNonZero(polygon)
        #expect(tess.origins.count == tess.vertices.count)

        for (i, origin) in tess.origins.enumerated() {
            #expect(origin.from >= 0 && origin.from < polygon.count)
            #expect(origin.to >= 0 && origin.to < polygon.count)
            #expect(origin.t >= 0 && origin.t <= 1)
            // 由来どおりに内分すると、その頂点の座標になる。
            let a = polygon[origin.from]
            let b = polygon[origin.to]
            let x = a.0 + (b.0 - a.0) * origin.t
            let y = a.1 + (b.1 - a.1) * origin.t
            #expect(abs(x - tess.vertices[i].0) < 1e-4)
            #expect(abs(y - tess.vertices[i].1) < 1e-4)
        }
    }
}
