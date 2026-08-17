import Metal
import simd

// MARK: - テキスト

extension Canvas2D {

    /// テキストサイズを設定します。
    ///
    /// Processing と同じく、行間（``textLeading(_:)``）は新しいフォントサイズから
    /// 導出される既定値へ戻ります。行間を指定するときは `textSize()` の**後**に
    /// ``textLeading(_:)`` を呼んでください。
    ///
    /// - Parameter size: フォントサイズ（ポイント単位）。
    public func textSize(_ size: Float) {
        currentTextSize = size
        currentTextLeading = nil
    }

    /// フォントファミリーを設定します。
    ///
    /// ``textSize(_:)`` と同じく行間は既定値へ戻ります。
    ///
    /// - Parameter family: フォントファミリー名。
    public func textFont(_ family: String) {
        currentFontFamily = family
        currentTextLeading = nil
    }

    /// 読み込み済みのフォントを設定します。
    ///
    /// ``MFont`` はプロセスへ登録済みのフォントを PostScript 名で指すため、内部の
    /// 保持形式はファミリー名指定と同じ文字列 1 本で済みます（`push`/`pop` でも保存されます）。
    ///
    /// - Parameter font: ``SketchContext/loadFont(_:cache:)`` が返したフォント。
    public func textFont(_ font: MFont) {
        currentFontFamily = font.postScriptName
        currentTextLeading = nil
    }

    /// テキストの揃え方を設定します。
    /// - Parameters:
    ///   - horizontal: 水平方向の揃え。
    ///   - vertical: 垂直方向の揃え。
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        currentTextAlignH = horizontal
        currentTextAlignV = vertical
    }

    /// テキストの行間（行の高さ）を設定します。
    ///
    /// Processing と同じく**ピクセル単位**で、隣り合う行のベースライン同士の距離に
    /// なります。``textSize(_:)`` / ``textFont(_:)`` を呼ぶと、新しいフォントから
    /// 導出される既定値へ戻ります。
    ///
    /// - Parameter leading: 行の高さ（ピクセル単位）。
    public func textLeading(_ leading: Float) {
        currentTextLeading = leading
    }

    /// 実際に使う行の高さ（ピクセル単位）。
    ///
    /// ``textLeading(_:)`` で明示されていればその値、していなければ Processing の
    /// `handleTextSize` と同じく `(ascent + descent) * 1.275` を使います。
    var effectiveTextLeading: Float {
        if let leading = currentTextLeading { return leading }
        let ascent = textRenderer.textAscent(
            fontSize: currentTextSize, fontFamily: currentFontFamily)
        let descent = textRenderer.textDescent(
            fontSize: currentTextSize, fontFamily: currentFontFamily)
        return (ascent + descent) * 1.275
    }

    /// テキスト文字列の幅を返します。
    ///
    /// 返るのは**1 文字ずつの advance（次の文字までの送り量）を足した幅**で、
    /// ``text(_:_:_:)`` が実際に文字を置く幅・``textAlign(_:_:)`` が揃えに使う幅と一致します。
    /// そのため加法的で（`textWidth("ab") == textWidth("a") + textWidth("b")`）、語ごとに
    /// 測って行を組めます。前後どちらの空白も幅に数えます。
    ///
    /// 墨面（インクの広がり）ではないので、`f` や斜体のようにはみ出す字形では
    /// 実際のインクが幅から少し出ることがあります。Processing と同じく隣り合う字の
    /// カーニングは掛かりません。
    ///
    /// 改行を含む文字列では、Processing と同じく**最も長い行**の幅を返します。
    ///
    /// - Parameter string: 計測するテキスト。
    /// - Returns: ピクセル単位の幅。
    public func textWidth(_ string: String) -> Float {
        Self.lines(of: string)
            .map { textRenderer.textWidth(string: $0, fontSize: currentTextSize, fontFamily: currentFontFamily) }
            .max() ?? 0
    }

    /// 文字列を改行で行へ分けます（`\r\n` と `\r` も改行として扱います）。
    ///
    /// 空行は残します — 空行ぶんだけ行送りする必要があるためです。
    static func lines(of string: String) -> [String] {
        string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
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
    ///
    /// 改行を含む文字列は行ごとに分けて描かれ、行の高さは ``textLeading(_:)`` に従います。
    /// 水平方向の揃えは行ごとの幅で、垂直方向の揃えは全行を 1 つのブロックとみなして
    /// 決まります（``TextAlignV/baseline`` は 1 行目のベースラインが `y` に来ます）。
    ///
    /// 文字は常に現在の fill 色で塗られます。``noFill()`` は図形にだけ効き、
    /// **テキストには効きません**（Processing は `noFill()` で文字が消えますが、metaphor の
    /// テキストに stroke 経路が無いため、あえて揃えていません。[#519] の判断）。
    /// 文字を出さないときは呼び出し自体をやめるか、`fill(255, 0)` のように
    /// アルファ 0 の fill を使ってください（アルファはグリフまで届きます）。
    ///
    /// [#519]: https://github.com/shinyaoguri/metaphor/issues/519
    ///
    /// - Parameters:
    ///   - string: 描画するテキスト。
    ///   - x: x座標。
    ///   - y: y座標。
    public func text(_ string: String, _ x: Float, _ y: Float) {
        svgRecorder?.recordUnsupported("text() (planned: textToPoints in Epic F)")
        guard !string.isEmpty else { return }

        let lines = Self.lines(of: string)
        guard lines.count > 1 else {
            drawTextLine(lines[0], x, y)
            return
        }

        // 2 行目以降がぶら下がるぶん、ブロック全体を垂直方向の揃えに合わせて持ち上げる。
        // 1 行のときは持ち上げ量が 0 になり、単一行の配置と完全に一致する。
        let leading = effectiveTextLeading
        let hangingHeight = Float(lines.count - 1) * leading
        var lineY = y
        switch currentTextAlignV {
        case .top, .baseline: break
        case .center: lineY -= hangingHeight / 2
        case .bottom: lineY -= hangingHeight
        }

        for line in lines {
            if !line.isEmpty { drawTextLine(line, x, lineY) }
            lineY += leading
        }
    }

    /// 改行を含まない 1 行を描画します（``text(_:_:_:)`` の実体）。
    private func drawTextLine(_ string: String, _ x: Float, _ y: Float) {
        guard !string.isEmpty else { return }

        if let (atlasTex, glyphs) = textRenderer.textGlyphs(
            string: string, fontSize: currentTextSize, fontFamily: currentFontFamily
        ), !glyphs.isEmpty {
            // 揃えの基準は advance の合計 = textWidth() が返す幅（#803）。最後のグリフの
            // ビットマップの右端（$0.x + $0.width）で測ると、アトラスへ書き込むときの
            // 余白 2px（TextRenderer の glyphW）が幅に混ざる。
            let totalWidth = textRenderer.textWidth(
                string: string, fontSize: currentTextSize, fontFamily: currentFontFamily)
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
    ///
    /// 行の高さは ``textLeading(_:)`` に従い、箱の高さに入り切らない行は
    /// Processing と同じく描かれません（箱でクリップされます）。
    ///
    /// 色の扱いは ``text(_:_:_:)`` と同じで、``noFill()`` はテキストに効きません。
    ///
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
            leading: effectiveTextLeading,
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
