import Metal
import AppKit
import CoreText

// MARK: - Text Alignment

/// Define horizontal text alignment options.
public enum TextAlignH: Sendable {
    case left, center, right
}

/// Define vertical text alignment options.
public enum TextAlignV: Sendable {
    case top, center, baseline, bottom
}

// MARK: - Glyph Info

/// Store information about a single glyph within the glyph atlas.
struct GlyphInfo {
    /// UV coordinates within the atlas (0.0 to 1.0).
    let u0: Float, v0: Float, u1: Float, v1: Float
    /// Size in pixels.
    let width: Float, height: Float
    /// Horizontal offset from the baseline.
    let bearingX: Float
    /// Vertical offset from the baseline (positive is upward).
    let bearingY: Float
    /// Horizontal distance to the next character.
    let advance: Float
}

/// Represent a positioned glyph ready for text drawing.
struct PositionedGlyph {
    let x: Float, y: Float
    let width: Float, height: Float
    let u0: Float, v0: Float, u1: Float, v1: Float
}

// MARK: - Glyph Atlas

/// Manage a glyph atlas per font and size using shelf packing.
@MainActor
final class GlyphAtlas {

    /// Serve as a cache key combining font family name and size.
    struct Key: Hashable {
        let fontFamily: String
        let fontSize: Float
    }

    private let device: MTLDevice
    private let fontSize: Float
    private let fontFamily: String
    private let font: CTFont

    /// Atlas texture containing rendered glyphs.
    private(set) var texture: MTLTexture?

    /// Current atlas dimensions.
    private var atlasWidth: Int
    private var atlasHeight: Int

    /// Mapping from characters to their glyph information.
    private var glyphMap: [Character: GlyphInfo] = [:]

    /// Shelf packing state.
    private var shelves: [Shelf] = []
    private var currentShelfY: Int = 0

    private struct Shelf {
        var y: Int
        var height: Int
        var nextX: Int
    }

    /// Maximum texture size for the atlas.
    private static let maxSize = 2048

    init(device: MTLDevice, fontFamily: String, fontSize: Float) {
        self.device = device
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        self.atlasWidth = 512
        self.atlasHeight = 512
        self.texture = createTexture(width: atlasWidth, height: atlasHeight)
    }

    /// Retrieve glyph information for a character, adding it to the atlas if necessary.
    ///
    /// - Parameter char: The character to look up.
    /// - Returns: The glyph information, or nil if the glyph could not be added.
    func glyph(for char: Character) -> GlyphInfo? {
        if let info = glyphMap[char] { return info }
        return addGlyph(char)
    }

    /// Generate an array of positioned glyphs for the given string.
    ///
    /// - Parameter string: The text to lay out.
    /// - Returns: An array of positioned glyphs, or nil if any glyph could not be resolved.
    func layoutGlyphs(string: String) -> [PositionedGlyph]? {
        var result: [PositionedGlyph] = []
        result.reserveCapacity(string.count)
        var cursorX: Float = 0

        for char in string {
            guard let g = glyph(for: char) else { return nil }
            result.append(PositionedGlyph(
                x: cursorX + g.bearingX,
                y: -g.bearingY,
                width: g.width,
                height: g.height,
                u0: g.u0, v0: g.v0, u1: g.u1, v1: g.v1
            ))
            cursorX += g.advance
        }
        return result
    }

    /// Calculate the total width of a string in pixels.
    ///
    /// - Parameter string: The text to measure.
    /// - Returns: The total advance width.
    func measureWidth(string: String) -> Float {
        var w: Float = 0
        for char in string {
            guard let g = glyph(for: char) else { return w }
            w += g.advance
        }
        return w
    }

    // MARK: - Private

    private func addGlyph(_ char: Character) -> GlyphInfo? {
        // Obtain glyph metrics via Core Text
        let str = String(char)
        let attrString = NSAttributedString(
            string: str,
            attributes: [.font: font, .foregroundColor: PlatformColor.white]
        )
        let line = CTLineCreateWithAttributedString(attrString)

        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let advance = Float(lineWidth)

        let glyphW = Int(ceil(lineWidth)) + 2
        let glyphH = Int(ceil(ascent + descent)) + 2
        guard glyphW > 0, glyphH > 0 else { return nil }

        // Find placement position in the atlas (shelf packing)
        guard let (px, py) = findSpace(width: glyphW, height: glyphH) else { return nil }

        // Render the glyph into a bitmap
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: glyphW, height: glyphH,
            bitsPerComponent: 8, bytesPerRow: glyphW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setTextDrawingMode(.fill)
        ctx.textPosition = CGPoint(x: 1, y: CGFloat(descent) + 1)
        CTLineDraw(line, ctx)

        // Write to the atlas texture
        guard let texture, let data = ctx.data else { return nil }
        let region = MTLRegion(
            origin: MTLOrigin(x: px, y: py, z: 0),
            size: MTLSize(width: glyphW, height: glyphH, depth: 1)
        )
        texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: glyphW * 4)

        let info = GlyphInfo(
            u0: Float(px) / Float(atlasWidth),
            v0: Float(py) / Float(atlasHeight),
            u1: Float(px + glyphW) / Float(atlasWidth),
            v1: Float(py + glyphH) / Float(atlasHeight),
            width: Float(glyphW),
            height: Float(glyphH),
            bearingX: 0,
            bearingY: Float(ascent) + 1,
            advance: advance
        )
        glyphMap[char] = info
        return info
    }

    private func findSpace(width: Int, height: Int) -> (Int, Int)? {
        // Check if it fits in an existing shelf
        for i in 0..<shelves.count {
            if shelves[i].height >= height && shelves[i].nextX + width <= atlasWidth {
                let pos = (shelves[i].nextX, shelves[i].y)
                shelves[i].nextX += width
                return pos
            }
        }

        // Create a new shelf
        if currentShelfY + height <= atlasHeight {
            let shelf = Shelf(y: currentShelfY, height: height, nextX: width)
            shelves.append(shelf)
            let pos = (0, currentShelfY)
            currentShelfY += height
            return pos
        }

        // Expand the atlas
        if atlasHeight < Self.maxSize {
            let newHeight = min(atlasHeight * 2, Self.maxSize)
            if let newTex = createTexture(width: atlasWidth, height: newHeight) {
                // Copy existing data
                copyTexture(from: texture!, to: newTex, width: atlasWidth, height: atlasHeight)
                texture = newTex

                // Recalculate UV coordinates (scale before updating atlasHeight)
                let scale = Float(atlasHeight) / Float(newHeight)
                var updated: [Character: GlyphInfo] = [:]
                for (char, old) in glyphMap {
                    updated[char] = GlyphInfo(
                        u0: old.u0, v0: old.v0 * scale,
                        u1: old.u1, v1: old.v1 * scale,
                        width: old.width, height: old.height,
                        bearingX: old.bearingX, bearingY: old.bearingY,
                        advance: old.advance
                    )
                }
                glyphMap = updated
                atlasHeight = newHeight

                // Retry with the new shelf
                return findSpace(width: width, height: height)
            }
        }

        return nil  // Atlas is full
    }

    private func createTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .managed
        return device.makeTexture(descriptor: desc)
    }

    private func copyTexture(from src: MTLTexture, to dst: MTLTexture, width: Int, height: Int) {
        // CPU-side copy (managed storage)
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height
        var buffer = [UInt8](repeating: 0, count: totalBytes)
        src.getBytes(&buffer, bytesPerRow: bytesPerRow,
                     from: MTLRegion(origin: .init(), size: .init(width: width, height: height, depth: 1)),
                     mipmapLevel: 0)
        dst.replace(region: MTLRegion(origin: .init(), size: .init(width: width, height: height, depth: 1)),
                    mipmapLevel: 0, withBytes: buffer, bytesPerRow: bytesPerRow)
    }
}

// MARK: - TextRenderer

/// Render text to MTLTexture using Core Text, with an LRU cache.
@MainActor
final class TextRenderer {
    private let device: MTLDevice
    private var cache: [TextCacheKey: CachedText] = [:]
    var maxCacheSize: Int = 256

    /// Glyph atlas cache, keyed by font and size.
    private var atlases: [GlyphAtlas.Key: GlyphAtlas] = [:]

    struct TextCacheKey: Hashable {
        let string: String
        let fontSize: Float
        let fontFamily: String
        let maxWidth: Float
        let maxHeight: Float
        let leading: Float

        /// Initialize a cache key for single-line text.
        init(string: String, fontSize: Float, fontFamily: String) {
            self.string = string
            self.fontSize = fontSize
            self.fontFamily = fontFamily
            self.maxWidth = 0
            self.maxHeight = 0
            self.leading = 0
        }

        /// Initialize a cache key for multi-line text.
        init(string: String, fontSize: Float, fontFamily: String,
             maxWidth: Float, maxHeight: Float, leading: Float) {
            self.string = string
            self.fontSize = fontSize
            self.fontFamily = fontFamily
            self.maxWidth = maxWidth
            self.maxHeight = maxHeight
            self.leading = leading
        }
    }

    struct CachedText {
        let texture: MTLTexture
        let width: Float
        let height: Float
        var lastUsedFrame: Int = 0
    }

    init(device: MTLDevice) {
        self.device = device
    }

    /// Retrieve a text texture from cache or render a new one.
    ///
    /// - Parameters:
    ///   - string: The text to render.
    ///   - fontSize: The font size in points.
    ///   - fontFamily: The font family name.
    ///   - frameCount: The current frame number for LRU tracking.
    /// - Returns: The cached text entry, or nil if rendering failed.
    func textTexture(
        string: String,
        fontSize: Float,
        fontFamily: String,
        frameCount: Int
    ) -> CachedText? {
        let key = TextCacheKey(string: string, fontSize: fontSize, fontFamily: fontFamily)

        if var cached = cache[key] {
            cached.lastUsedFrame = frameCount
            cache[key] = cached
            return cached
        }

        guard var result = renderText(string: string, fontSize: fontSize, fontFamily: fontFamily) else {
            return nil
        }
        result.lastUsedFrame = frameCount
        cache[key] = result

        if cache.count > maxCacheSize {
            evictOldest()
        }

        return result
    }

    /// Calculate the width of a text string without rendering it.
    ///
    /// - Parameters:
    ///   - string: The text to measure.
    ///   - fontSize: The font size in points.
    ///   - fontFamily: The font family name.
    /// - Returns: The width of the text in pixels.
    func textWidth(string: String, fontSize: Float, fontFamily: String) -> Float {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attrString = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        return Float(ceil(bounds.width))
    }

    /// Retrieve the font ascent (the height above the baseline).
    ///
    /// - Parameters:
    ///   - fontSize: The font size in points.
    ///   - fontFamily: The font family name.
    /// - Returns: The ascent value in pixels.
    func textAscent(fontSize: Float, fontFamily: String) -> Float {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        return Float(CTFontGetAscent(font))
    }

    /// Retrieve the font descent (the height below the baseline, as a positive value).
    ///
    /// - Parameters:
    ///   - fontSize: The font size in points.
    ///   - fontFamily: The font family name.
    /// - Returns: The descent value in pixels.
    func textDescent(fontSize: Float, fontFamily: String) -> Float {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        return Float(CTFontGetDescent(font))
    }

    /// Retrieve a multi-line text texture from cache or render a new one using CTFramesetter for word wrapping.
    ///
    /// - Parameters:
    ///   - string: The text to render.
    ///   - fontSize: The font size in points.
    ///   - fontFamily: The font family name.
    ///   - maxWidth: The maximum width for line wrapping.
    ///   - maxHeight: The maximum height, or 0 for unlimited.
    ///   - leading: The line spacing multiplier.
    ///   - frameCount: The current frame number for LRU tracking.
    /// - Returns: The cached text entry, or nil if rendering failed.
    func textTextureMultiline(
        string: String,
        fontSize: Float,
        fontFamily: String,
        maxWidth: Float,
        maxHeight: Float,
        leading: Float,
        frameCount: Int
    ) -> CachedText? {
        let key = TextCacheKey(
            string: string, fontSize: fontSize, fontFamily: fontFamily,
            maxWidth: maxWidth, maxHeight: maxHeight, leading: leading
        )

        if var cached = cache[key] {
            cached.lastUsedFrame = frameCount
            cache[key] = cached
            return cached
        }

        guard var result = renderTextMultiline(
            string: string, fontSize: fontSize, fontFamily: fontFamily,
            maxWidth: maxWidth, maxHeight: maxHeight, leading: leading
        ) else { return nil }

        result.lastUsedFrame = frameCount
        cache[key] = result

        if cache.count > maxCacheSize {
            evictOldest()
        }

        return result
    }

    // MARK: - Atlas API

    /// Retrieve the glyph atlas for the given font, creating one if necessary.
    ///
    /// - Parameters:
    ///   - fontSize: The font size in points.
    ///   - fontFamily: The font family name.
    /// - Returns: The glyph atlas for the specified font and size.
    func getAtlas(fontSize: Float, fontFamily: String) -> GlyphAtlas {
        let key = GlyphAtlas.Key(fontFamily: fontFamily, fontSize: fontSize)
        if let atlas = atlases[key] { return atlas }
        let atlas = GlyphAtlas(device: device, fontFamily: fontFamily, fontSize: fontSize)
        atlases[key] = atlas
        return atlas
    }

    /// Retrieve positioned glyphs from the atlas for the given string.
    ///
    /// - Parameters:
    ///   - string: The text to lay out.
    ///   - fontSize: The font size in points.
    ///   - fontFamily: The font family name.
    /// - Returns: A tuple of the atlas texture and positioned glyphs, or nil if any glyph could not fit in the atlas.
    func textGlyphs(
        string: String,
        fontSize: Float,
        fontFamily: String
    ) -> (texture: MTLTexture, glyphs: [PositionedGlyph])? {
        let atlas = getAtlas(fontSize: fontSize, fontFamily: fontFamily)
        guard let glyphs = atlas.layoutGlyphs(string: string),
              let texture = atlas.texture else { return nil }
        return (texture, glyphs)
    }

    // MARK: - Private

    private func renderText(string: String, fontSize: Float, fontFamily: String) -> CachedText? {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: PlatformColor.white
        ]
        let attrString = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let texWidth = Int(ceil(bounds.width)) + 4
        let texHeight = Int(ceil(bounds.height)) + 4
        guard texWidth > 0, texHeight > 0 else { return nil }

        // CGBitmapContext (RGBA premultiplied)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: texWidth,
            height: texHeight,
            bitsPerComponent: 8,
            bytesPerRow: texWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw white text on a transparent background
        ctx.setTextDrawingMode(.fill)
        let originX = -bounds.origin.x + 2
        let originY = -bounds.origin.y + 2
        ctx.textPosition = CGPoint(x: originX, y: originY)
        CTLineDraw(line, ctx)

        // Upload to MTLTexture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: texWidth,
            height: texHeight,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .managed

        guard let texture = device.makeTexture(descriptor: descriptor),
              let data = ctx.data else { return nil }

        texture.replace(
            region: MTLRegionMake2D(0, 0, texWidth, texHeight),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: texWidth * 4
        )

        return CachedText(texture: texture, width: Float(texWidth), height: Float(texHeight))
    }

    private func renderTextMultiline(
        string: String, fontSize: Float, fontFamily: String,
        maxWidth: Float, maxHeight: Float, leading: Float
    ) -> CachedText? {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)

        // Paragraph style (line spacing)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(fontSize) * CGFloat(leading - 1.0)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: PlatformColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let attrString = NSAttributedString(string: string, attributes: attributes)

        // Lay out with CTFramesetter
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)

        let constraintSize = CGSize(
            width: CGFloat(maxWidth),
            height: maxHeight > 0 ? CGFloat(maxHeight) : CGFloat.greatestFiniteMagnitude
        )
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil, constraintSize, nil
        )

        let texWidth = Int(ceil(suggestedSize.width)) + 4
        let texHeight = Int(ceil(suggestedSize.height)) + 4
        guard texWidth > 0, texHeight > 0 else { return nil }

        // CGBitmapContext (RGBA premultiplied)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: texWidth,
            height: texHeight,
            bitsPerComponent: 8,
            bytesPerRow: texWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // CoreText uses bottom-left origin. CGBitmapContext also uses bottom-left origin.
        // However, textures use top-left origin, so flip vertically before drawing.
        ctx.translateBy(x: 0, y: CGFloat(texHeight))
        ctx.scaleBy(x: 1.0, y: -1.0)

        // Create and draw the text frame
        let framePath = CGPath(
            rect: CGRect(x: 2, y: 2, width: texWidth - 4, height: texHeight - 4),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), framePath, nil
        )
        CTFrameDraw(frame, ctx)

        // Upload to MTLTexture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: texWidth,
            height: texHeight,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .managed

        guard let texture = device.makeTexture(descriptor: descriptor),
              let data = ctx.data else { return nil }

        texture.replace(
            region: MTLRegionMake2D(0, 0, texWidth, texHeight),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: texWidth * 4
        )

        return CachedText(texture: texture, width: Float(texWidth), height: Float(texHeight))
    }

    private func evictOldest() {
        let sorted = cache.sorted { $0.value.lastUsedFrame < $1.value.lastUsedFrame }
        let removeCount = cache.count - maxCacheSize / 2
        for (key, _) in sorted.prefix(removeCount) {
            cache.removeValue(forKey: key)
        }
    }
}
