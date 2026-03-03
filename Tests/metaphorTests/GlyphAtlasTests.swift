import XCTest
@testable import metaphor
@testable import MetaphorCore

@MainActor
final class GlyphAtlasTests: XCTestCase {

    // MARK: - Helpers

    private func makeDevice() -> MTLDevice? {
        MTLCreateSystemDefaultDevice()
    }

    // MARK: - GlyphAtlas Tests

    func testAtlasCreation() {
        guard let device = makeDevice() else { return }
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 32)
        XCTAssertNotNil(atlas.texture)
    }

    func testGlyphCaching() {
        guard let device = makeDevice() else { return }
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 32)
        let g1 = atlas.glyph(for: "A")
        let g2 = atlas.glyph(for: "A")
        XCTAssertNotNil(g1)
        XCTAssertNotNil(g2)
        // 同じ文字は同じ UV を返す
        XCTAssertEqual(g1!.u0, g2!.u0)
        XCTAssertEqual(g1!.v0, g2!.v0)
    }

    func testDifferentGlyphsDifferentUVs() {
        guard let device = makeDevice() else { return }
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 32)
        let gA = atlas.glyph(for: "A")
        let gB = atlas.glyph(for: "B")
        XCTAssertNotNil(gA)
        XCTAssertNotNil(gB)
        // 異なる文字は異なる UV を持つ
        XCTAssertTrue(gA!.u0 != gB!.u0 || gA!.v0 != gB!.v0)
    }

    func testGlyphMetrics() {
        guard let device = makeDevice() else { return }
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 32)
        let g = atlas.glyph(for: "W")
        XCTAssertNotNil(g)
        XCTAssertGreaterThan(g!.width, 0)
        XCTAssertGreaterThan(g!.height, 0)
        XCTAssertGreaterThan(g!.advance, 0)
        XCTAssertGreaterThan(g!.bearingY, 0)
    }

    func testLayoutGlyphs() {
        guard let device = makeDevice() else { return }
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 24)
        let glyphs = atlas.layoutGlyphs(string: "Hello")
        XCTAssertNotNil(glyphs)
        XCTAssertEqual(glyphs!.count, 5)

        // x 座標は単調増加
        for i in 1..<glyphs!.count {
            XCTAssertGreaterThan(glyphs![i].x, glyphs![i - 1].x)
        }
    }

    func testLayoutEmptyString() {
        guard let device = makeDevice() else { return }
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 24)
        let glyphs = atlas.layoutGlyphs(string: "")
        XCTAssertNotNil(glyphs)
        XCTAssertEqual(glyphs!.count, 0)
    }

    func testMeasureWidth() {
        guard let device = makeDevice() else { return }
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 24)
        let w1 = atlas.measureWidth(string: "i")
        let w2 = atlas.measureWidth(string: "WWW")
        XCTAssertGreaterThan(w1, 0)
        XCTAssertGreaterThan(w2, w1)
    }

    func testManyCharactersFillAtlas() {
        guard let device = makeDevice() else { return }
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 48)
        // ASCII 印字可能文字を全部追加
        for scalar in (32...126) {
            let char = Character(UnicodeScalar(scalar)!)
            let g = atlas.glyph(for: char)
            XCTAssertNotNil(g, "Failed for character: \(char)")
        }
    }

    // MARK: - TextRenderer Atlas Integration

    func testTextRendererAtlasIntegration() {
        guard let device = makeDevice() else { return }
        let renderer = TextRenderer(device: device)
        let result = renderer.textGlyphs(string: "Test", fontSize: 24, fontFamily: "Helvetica")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.glyphs.count, 4)
        XCTAssertNotNil(result!.texture)
    }

    func testAtlasKeyDifferentSizes() {
        guard let device = makeDevice() else { return }
        let renderer = TextRenderer(device: device)
        let r1 = renderer.textGlyphs(string: "A", fontSize: 16, fontFamily: "Helvetica")
        let r2 = renderer.textGlyphs(string: "A", fontSize: 32, fontFamily: "Helvetica")
        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
        // 異なるフォントサイズは異なるアトラステクスチャを使う
        XCTAssertTrue(r1!.texture !== r2!.texture)
    }

    func testMaxCacheSizeConfigurable() {
        guard let device = makeDevice() else { return }
        let renderer = TextRenderer(device: device)
        renderer.maxCacheSize = 128
        XCTAssertEqual(renderer.maxCacheSize, 128)
    }
}
