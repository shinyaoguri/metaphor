import Foundation
import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore

// MARK: - textToPoints / textToContours / textToShape (#650)

@Suite("TextToPoints", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct TextToPointsTests {

    /// アウトラインの形が書体に依存するテストは、システムに必ずある書体で固定する。
    private static let font = "Helvetica"

    private func makeContext(size: Float = 64) throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 256, height: 256)
        let context = SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
        context.textFont(Self.font)
        context.textSize(size)
        return context
    }

    private func boundingBox(_ points: [Vec2]) -> (minX: Float, minY: Float, maxX: Float, maxY: Float) {
        (points.map(\.x).min()!, points.map(\.y).min()!,
         points.map(\.x).max()!, points.map(\.y).max()!)
    }

    // MARK: - 輪郭の数

    @Test("contour counts match the glyph topology", arguments: [
        ("l", 1),   // 単純な軸のみ
        ("o", 2),   // 外周 + 穴
        ("i", 2),   // 点と軸（穴ではなく離れた外周が 2 つ）
        ("B", 3),   // 外周 + 穴 2 つ
    ])
    func contourCounts(character: String, expected: Int) throws {
        let context = try makeContext()
        let contours = context.textToContours(character, 0, 0)
        #expect(contours.count == expected)
    }

    @Test("holes are nested under the enclosing outer contour")
    func holeNesting() throws {
        let context = try makeContext()
        // "o" は外周 1 + 穴 1、"i" は離れた外周 2（穴なし）
        let o = ContourNesting.group(context.textToContours("o", 0, 0))
        #expect(o.count == 1)
        #expect(o.first?.holes.count == 1)

        let i = ContourNesting.group(context.textToContours("i", 0, 0))
        #expect(i.count == 2)
        #expect(i.allSatisfy { $0.holes.isEmpty })
    }

    // MARK: - 座標系

    @Test("outline sits on the baseline in metaphor's y-down space")
    func baselineAndOrientation() throws {
        let context = try makeContext()
        // textAlign は既定の (.left, .baseline)。原点 (0, 0) はベースライン左端。
        let box = boundingBox(context.textToPoints("H", 0, 0))
        let ascent = context.canvas.textAscent()
        let descent = context.canvas.textDescent()

        // 大文字 H はベースラインより上（y 下向きなので負）に立ち、下へは出ない
        #expect(box.maxY <= 1)
        #expect(box.minY < 0)
        // 高さは ascent の範囲に収まる（cap height < ascent）
        #expect(-box.minY <= ascent + 1)
        #expect(descent > 0)
        // 左端はほぼ原点、右端は幅の範囲
        #expect(box.minX >= -1)
        #expect(box.maxX <= context.canvas.textWidth("H") + 1)
    }

    @Test("descenders extend below the baseline")
    func descender() throws {
        let context = try makeContext()
        let box = boundingBox(context.textToPoints("p", 0, 0))
        #expect(box.maxY > 1)  // ベースラインより下（y 下向き）へ出る
        // ベースラインより上（x ハイト）のほうが下（ディセンダ）より高い。
        // y の反転を落とすと minY と maxY が入れ替わるので、ここで捕まる。
        #expect(-box.minY > box.maxY)
    }

    @Test("translating x and y translates the outline")
    func translation() throws {
        let context = try makeContext()
        let base = boundingBox(context.textToPoints("A", 0, 0))
        let moved = boundingBox(context.textToPoints("A", 100, 50))
        #expect(abs((moved.minX - base.minX) - 100) < 0.01)
        #expect(abs((moved.minY - base.minY) - 50) < 0.01)
    }

    // MARK: - textAlign との整合

    @Test("textAlign(.center) centers the outline on x")
    func centerAlign() throws {
        let context = try makeContext()
        context.textAlign(.center, .baseline)
        let box = boundingBox(context.textToPoints("metaphor", 100, 0))
        let center = (box.minX + box.maxX) / 2
        // 光学バウンズと advance 幅の差があるので数 px の許容を置く
        #expect(abs(center - 100) < 4)
    }

    @Test("textAlign(.top) pushes the outline below y")
    func topAlign() throws {
        let context = try makeContext()
        let ascent = context.canvas.textAscent()
        context.textAlign(.left, .top)
        let box = boundingBox(context.textToPoints("H", 0, 0))
        // 上揃えなら y より下にだけ描かれ、下端はベースライン（= y + ascent）を越えない
        #expect(box.minY >= -1)
        #expect(box.maxY <= ascent + 1)
    }

    // MARK: - sampleFactor

    @Test("a larger sampleFactor yields more points")
    func sampleFactorMonotonicity() throws {
        let context = try makeContext()
        let coarse = context.textToPoints("o", 0, 0, sampleFactor: 0.05).count
        let fine = context.textToPoints("o", 0, 0, sampleFactor: 0.5).count
        #expect(coarse > 0)
        #expect(fine > coarse)
    }

    @Test("a non-positive sampleFactor returns no points")
    func invalidSampleFactor() throws {
        let context = try makeContext()
        #expect(context.textToPoints("o", 0, 0, sampleFactor: 0).isEmpty)
    }

    // MARK: - 縮退入力

    @Test("empty and outline-less strings return empty")
    func degenerateInput() throws {
        let context = try makeContext()
        #expect(context.textToPoints("", 0, 0).isEmpty)
        #expect(context.textToContours("", 0, 0).isEmpty)
        #expect(context.textToPoints("   ", 0, 0).isEmpty)  // 空白は輪郭を持たない
    }

    // MARK: - textToShape

    @Test("textToShape builds one child per outer contour, holes as contours")
    func shapeStructure() throws {
        let context = try makeContext()
        let shape = context.textToShape("o", 0, 0)
        #expect(shape.children.count == 1)
        let child = try #require(shape.children.first)
        #expect(child.kind.isPath)
        #expect(child.contourRanges.count == 1)  // "o" の穴
        #expect(child.vertices2D.count > child.contourRanges[0].count)
    }

    @Test("textToShape covers every glyph of a word")
    func shapeCoversWord() throws {
        let context = try makeContext()
        // "metaphor" の外周は 8 文字ぶん。穴を持つのは e/a/p/o の 4 文字
        let shape = context.textToShape("metaphor", 0, 0)
        #expect(shape.children.count == 8)
        let withHoles = shape.children.filter { !$0.contourRanges.isEmpty }
        #expect(withHoles.count == 4)
    }

    @Test("textToShape geometry matches textToContours")
    func shapeMatchesContours() throws {
        let context = try makeContext()
        let contours = context.textToContours("o", 10, 20)
        let shape = context.textToShape("o", 10, 20)
        let shapePoints = shape.children.flatMap { $0.vertices2D.map(\.position) }
        #expect(shapePoints.count == contours.reduce(0) { $0 + $1.count })
    }
}
