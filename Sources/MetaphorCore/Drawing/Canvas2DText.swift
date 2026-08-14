import Metal
import simd

// MARK: - テキスト

extension Canvas2D {

    /// テキストサイズを設定します。
    /// - Parameter size: フォントサイズ（ポイント単位）。
    public func textSize(_ size: Float) {
        currentTextSize = size
    }

    /// フォントファミリーを設定します。
    /// - Parameter family: フォントファミリー名。
    public func textFont(_ family: String) {
        currentFontFamily = family
    }

    /// 読み込み済みのフォントを設定します。
    ///
    /// ``MFont`` はプロセスへ登録済みのフォントを PostScript 名で指すため、内部の
    /// 保持形式はファミリー名指定と同じ文字列 1 本で済みます（`push`/`pop` でも保存されます）。
    ///
    /// - Parameter font: ``SketchContext/loadFont(_:cache:)`` が返したフォント。
    public func textFont(_ font: MFont) {
        currentFontFamily = font.postScriptName
    }

    /// テキストの揃え方を設定します。
    /// - Parameters:
    ///   - horizontal: 水平方向の揃え。
    ///   - vertical: 垂直方向の揃え。
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        currentTextAlignH = horizontal
        currentTextAlignV = vertical
    }

    /// テキストの行間を設定します（1.0 = 詰め、1.2 = デフォルト）。
    /// - Parameter leading: 行間の倍率。
    public func textLeading(_ leading: Float) {
        currentTextLeading = leading
    }

    /// テキスト文字列のレンダリング後の幅を返します。
    /// - Parameter string: 計測するテキスト。
    /// - Returns: ピクセル単位の幅。
    public func textWidth(_ string: String) -> Float {
        textRenderer.textWidth(string: string, fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// 現在のフォントのアセントを返します。
    /// - Returns: ピクセル単位のフォントアセント。
    public func textAscent() -> Float {
        textRenderer.textAscent(fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// 現在のフォントのディセントを返します。
    /// - Returns: ピクセル単位のフォントディセント。
    public func textDescent() -> Float {
        textRenderer.textDescent(fontSize: currentTextSize, fontFamily: currentFontFamily)
    }

    /// テキストの基準点 `(x, y)` を、現在の ``textAlign(_:_:)`` からベースライン左端へ
    /// 変換します。
    ///
    /// 描画（`text()`）とアウトライン取得（``textToContours(_:_:_:sampleFactor:)``）で
    /// 同じ配置になるよう、変換はここ 1 か所に置きます。
    ///
    /// - Parameters:
    ///   - x: 呼び出し側が指定した x。
    ///   - y: 呼び出し側が指定した y。
    ///   - width: 配置対象のテキスト幅。
    /// - Returns: ベースライン左端の座標。
    func textBaselineOrigin(x: Float, y: Float, width: Float) -> (x: Float, y: Float) {
        let ascent = textRenderer.textAscent(
            fontSize: currentTextSize, fontFamily: currentFontFamily)
        let descent = textRenderer.textDescent(
            fontSize: currentTextSize, fontFamily: currentFontFamily)

        var originX = x
        switch currentTextAlignH {
        case .left: break
        case .center: originX -= width / 2
        case .right: originX -= width
        }

        var originY = y
        switch currentTextAlignV {
        case .top: originY += ascent
        case .center: originY += ascent - (ascent + descent) / 2
        case .baseline: break
        case .bottom: originY -= descent
        }
        return (originX, originY)
    }

    /// 指定位置にテキスト文字列を描画します。
    /// - Parameters:
    ///   - string: 描画するテキスト。
    ///   - x: x座標。
    ///   - y: y座標。
    public func text(_ string: String, _ x: Float, _ y: Float) {
        svgRecorder?.recordUnsupported("text() (planned: textToPoints in Epic F)")
        guard !string.isEmpty else { return }

        if let (atlasTex, glyphs) = textRenderer.textGlyphs(
            string: string, fontSize: currentTextSize, fontFamily: currentFontFamily
        ), !glyphs.isEmpty {
            let totalWidth = glyphs.last.map { $0.x + $0.width } ?? 0
            // drawTextFromAtlas の y は「ベースライン」位置（PositionedGlyph の座標が
            // ベースライン基準のため）。textBaselineOrigin が各揃えモードから変換する。
            let origin = textBaselineOrigin(x: x, y: y, width: totalWidth)
            drawTextFromAtlas(texture: atlasTex, glyphs: glyphs, x: origin.x, y: origin.y)
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

        // アトラス経路と同じく fill 色で塗る（tint は image() 用、#516）
        drawTexturedQuad(
            texture: cached.texture, x: drawX, y: drawY, w: cached.width, h: cached.height,
            color: fillColor
        )
    }

    /// バウンディングボックス内に自動改行付きでテキストを描画します。
    /// - Parameters:
    ///   - string: 描画するテキスト。
    ///   - x: バウンディングボックスのx座標。
    ///   - y: バウンディングボックスのy座標。
    ///   - w: バウンディングボックスの幅。
    ///   - h: バウンディングボックスの高さ。
    public func text(_ string: String, _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        svgRecorder?.recordUnsupported("text() (planned: textToPoints in Epic F)")
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

        // 3 引数版と同じく fill 色で塗る（tint は image() 用、#516）
        drawTexturedQuad(
            texture: cached.texture, x: drawX, y: drawY, w: cached.width, h: cached.height,
            color: fillColor
        )
    }
}
