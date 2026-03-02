import Metal
import simd

// MARK: - Text

extension Canvas2D {

    /// Set the text size.
    /// - Parameter size: Font size in points.
    public func textSize(_ size: Float) {
        currentTextSize = size
    }

    /// Set the font family.
    /// - Parameter family: Font family name.
    public func textFont(_ family: String) {
        currentFontFamily = family
    }

    /// Set the text alignment.
    /// - Parameters:
    ///   - horizontal: Horizontal alignment.
    ///   - vertical: Vertical alignment.
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        currentTextAlignH = horizontal
        currentTextAlignV = vertical
    }

    /// Set the text line spacing (1.0 = tight, 1.2 = default).
    /// - Parameter leading: Line spacing multiplier.
    public func textLeading(_ leading: Float) {
        currentTextLeading = leading
    }

    /// Return the rendered width of a text string.
    /// - Parameter string: The text to measure.
    /// - Returns: The width in pixels.
    public func textWidth(_ string: String) -> Float {
        textRenderer.textWidth(string: string, fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// Return the ascent of the current font.
    /// - Returns: The font ascent in pixels.
    public func textAscent() -> Float {
        textRenderer.textAscent(fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// Return the descent of the current font.
    /// - Returns: The font descent in pixels.
    public func textDescent() -> Float {
        textRenderer.textDescent(fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// Draw a text string at the specified position.
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    public func text(_ string: String, _ x: Float, _ y: Float) {
        guard !string.isEmpty else { return }

        if let (atlasTex, glyphs) = textRenderer.textGlyphs(
            string: string, fontSize: currentTextSize, fontFamily: currentFontFamily
        ), !glyphs.isEmpty {
            let totalWidth = glyphs.last.map { $0.x + $0.width } ?? 0
            let ascent = textRenderer.textAscent(fontSize: currentTextSize, fontFamily: currentFontFamily)
            let descent = textRenderer.textDescent(fontSize: currentTextSize, fontFamily: currentFontFamily)
            let totalHeight = ascent + descent

            var drawX = x
            var drawY = y
            switch currentTextAlignH {
            case .left: break
            case .center: drawX -= totalWidth / 2
            case .right: drawX -= totalWidth
            }
            switch currentTextAlignV {
            case .top: break
            case .center: drawY -= totalHeight / 2
            case .baseline: drawY -= ascent
            case .bottom: drawY -= totalHeight
            }

            drawTextFromAtlas(texture: atlasTex, glyphs: glyphs, x: drawX, y: drawY)
            return
        }

        guard let cached = textRenderer.textTexture(
            string: string,
            fontSize: currentTextSize,
            fontFamily: currentFontFamily,
            frameCount: frameCounter
        ) else { return }

        var drawX = x
        var drawY = y
        switch currentTextAlignH {
        case .left: break
        case .center: drawX -= cached.width / 2
        case .right: drawX -= cached.width
        }
        switch currentTextAlignV {
        case .top: break
        case .center: drawY -= cached.height / 2
        case .baseline: drawY -= cached.height * 0.8
        case .bottom: drawY -= cached.height
        }

        drawTexturedQuad(texture: cached.texture, x: drawX, y: drawY, w: cached.width, h: cached.height)
    }

    /// Draw text within a bounding box with automatic word wrapping.
    /// - Parameters:
    ///   - string: The text to draw.
    ///   - x: X coordinate of the bounding box.
    ///   - y: Y coordinate of the bounding box.
    ///   - w: Width of the bounding box.
    ///   - h: Height of the bounding box.
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        guard !string.isEmpty else { return }
        guard let cached = textRenderer.textTextureMultiline(
            string: string,
            fontSize: currentTextSize,
            fontFamily: currentFontFamily,
            maxWidth: w,
            maxHeight: h,
            leading: currentTextLeading,
            frameCount: frameCounter
        ) else { return }

        var drawX = x
        var drawY = y
        switch currentTextAlignH {
        case .left: break
        case .center: drawX += (w - cached.width) / 2
        case .right: drawX += w - cached.width
        }
        switch currentTextAlignV {
        case .top: break
        case .center: drawY += (h - cached.height) / 2
        case .baseline: drawY += (h - cached.height) * 0.8
        case .bottom: drawY += h - cached.height
        }

        drawTexturedQuad(texture: cached.texture, x: drawX, y: drawY, w: cached.width, h: cached.height)
    }
}
