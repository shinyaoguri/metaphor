import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

@Suite("GlyphAtlas", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct GlyphAtlasTests {

    @Test("atlas creation")
    func atlasCreation() {
        let device = MetalTestHelper.device!
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 32)
        #expect(atlas.texture != nil)
    }

    @Test("glyph caching returns same UVs")
    func glyphCaching() {
        let device = MetalTestHelper.device!
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 32)
        let g1 = atlas.glyph(for: "A")
        let g2 = atlas.glyph(for: "A")
        #expect(g1 != nil)
        #expect(g2 != nil)
        #expect(g1!.u0 == g2!.u0)
        #expect(g1!.v0 == g2!.v0)
    }

    @Test("different glyphs have different UVs")
    func differentGlyphs() {
        let device = MetalTestHelper.device!
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 32)
        let gA = atlas.glyph(for: "A")
        let gB = atlas.glyph(for: "B")
        #expect(gA != nil)
        #expect(gB != nil)
        #expect(gA!.u0 != gB!.u0 || gA!.v0 != gB!.v0)
    }

    @Test("glyph metrics are valid")
    func glyphMetrics() {
        let device = MetalTestHelper.device!
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 32)
        let g = atlas.glyph(for: "W")
        #expect(g != nil)
        #expect(g!.width > 0)
        #expect(g!.height > 0)
        #expect(g!.advance > 0)
        #expect(g!.bearingY > 0)
    }

    @Test("layoutGlyphs for Hello")
    func layoutGlyphs() {
        let device = MetalTestHelper.device!
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 24)
        let glyphs = atlas.layoutGlyphs(string: "Hello")
        #expect(glyphs != nil)
        #expect(glyphs!.count == 5)
        for i in 1..<glyphs!.count {
            #expect(glyphs![i].x > glyphs![i - 1].x)
        }
    }

    @Test("layoutGlyphs empty string")
    func layoutEmpty() {
        let device = MetalTestHelper.device!
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 24)
        let glyphs = atlas.layoutGlyphs(string: "")
        #expect(glyphs != nil)
        #expect(glyphs!.count == 0)
    }

    @Test("measureWidth increases with more characters")
    func measureWidth() {
        let device = MetalTestHelper.device!
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 24)
        let w1 = atlas.measureWidth(string: "i")
        let w2 = atlas.measureWidth(string: "WWW")
        #expect(w1 > 0)
        #expect(w2 > w1)
    }

    @Test("many characters fill atlas without crash")
    func manyCharacters() {
        let device = MetalTestHelper.device!
        let atlas = GlyphAtlas(device: device, fontFamily: "Helvetica", fontSize: 48)
        for scalar in (32...126) {
            let char = Character(UnicodeScalar(scalar)!)
            let g = atlas.glyph(for: char)
            #expect(g != nil, "Failed for character: \(char)")
        }
    }
}

// MARK: - TextRenderer Atlas Integration

@Suite("TextRenderer Atlas", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct TextRendererAtlasTests {

    @Test("textGlyphs returns correct count")
    func textGlyphs() {
        let device = MetalTestHelper.device!
        let renderer = TextRenderer(device: device)
        let result = renderer.textGlyphs(string: "Test", fontSize: 24, fontFamily: "Helvetica")
        #expect(result != nil)
        #expect(result!.glyphs.count == 4)
        #expect(result!.texture != nil)
    }

    @Test("different font sizes use different atlas textures")
    func differentSizes() {
        let device = MetalTestHelper.device!
        let renderer = TextRenderer(device: device)
        let r1 = renderer.textGlyphs(string: "A", fontSize: 16, fontFamily: "Helvetica")
        let r2 = renderer.textGlyphs(string: "A", fontSize: 32, fontFamily: "Helvetica")
        #expect(r1 != nil)
        #expect(r2 != nil)
        #expect(r1!.texture !== r2!.texture)
    }

    @Test("maxCacheSize is configurable")
    func maxCacheSize() {
        let device = MetalTestHelper.device!
        let renderer = TextRenderer(device: device)
        renderer.maxCacheSize = 128
        #expect(renderer.maxCacheSize == 128)
    }
}
