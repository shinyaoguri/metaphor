import Metal
import simd

// MARK: - Text

extension Canvas2D {

    /// テキストサイズを設定
    public func textSize(_ size: Float) {
        currentTextSize = size
    }

    /// フォントを設定
    public func textFont(_ family: String) {
        currentFontFamily = family
    }

    /// テキスト揃えを設定
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        currentTextAlignH = horizontal
        currentTextAlignV = vertical
    }

    /// テキストの行間を設定（1.0=ぴったり、1.2=デフォルト）
    public func textLeading(_ leading: Float) {
        currentTextLeading = leading
    }

    /// テキストの描画幅を取得
    public func textWidth(_ string: String) -> Float {
        textRenderer.textWidth(string: string, fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// フォントのアセントを取得
    public func textAscent() -> Float {
        textRenderer.textAscent(fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// フォントのディセントを取得
    public func textDescent() -> Float {
        textRenderer.textDescent(fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// テキストを描画
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

    /// ボックス内にテキストを描画（自動折り返し）
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
