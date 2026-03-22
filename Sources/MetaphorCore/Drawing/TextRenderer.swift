import Metal
import AppKit
import CoreText

// MARK: - Text Alignment

/// 水平方向のテキスト配置オプションを定義します。
public enum TextAlignH: Sendable {
    case left, center, right
}

/// 垂直方向のテキスト配置オプションを定義します。
public enum TextAlignV: Sendable {
    case top, center, baseline, bottom
}

// MARK: - Glyph Info

/// グリフアトラス内の単一グリフに関する情報を格納します。
struct GlyphInfo {
    /// アトラス内の UV 座標（0.0〜1.0）。
    let u0: Float, v0: Float, u1: Float, v1: Float
    /// ピクセル単位のサイズ。
    let width: Float, height: Float
    /// ベースラインからの水平オフセット。
    let bearingX: Float
    /// ベースラインからの垂直オフセット（正の値は上向き）。
    let bearingY: Float
    /// 次の文字までの水平距離。
    let advance: Float
}

/// テキスト描画の準備ができた配置済みグリフを表現します。
struct PositionedGlyph {
    let x: Float, y: Float
    let width: Float, height: Float
    let u0: Float, v0: Float, u1: Float, v1: Float
}

// MARK: - Glyph Atlas

/// シェルフパッキングを使用してフォントとサイズごとのグリフアトラスを管理します。
@MainActor
final class GlyphAtlas {

    /// フォントファミリー名とサイズを組み合わせたキャッシュキー。
    struct Key: Hashable {
        let fontFamily: String
        let fontSize: Float
    }

    private let device: MTLDevice
    private let fontSize: Float
    private let fontFamily: String
    private let font: CTFont

    /// レンダリング済みグリフを含むアトラステクスチャ。
    private(set) var texture: MTLTexture?

    /// 現在のアトラスの寸法。
    private var atlasWidth: Int
    private var atlasHeight: Int

    /// 文字からグリフ情報へのマッピング。
    private var glyphMap: [Character: GlyphInfo] = [:]

    /// シェルフパッキングの状態。
    private var shelves: [Shelf] = []
    private var currentShelfY: Int = 0

    private struct Shelf {
        var y: Int
        var height: Int
        var nextX: Int
    }

    /// アトラスの最大テクスチャサイズ。
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

    /// 文字のグリフ情報を取得し、必要に応じてアトラスに追加します。
    ///
    /// - Parameter char: 検索する文字。
    /// - Returns: グリフ情報。グリフを追加できなかった場合は nil。
    func glyph(for char: Character) -> GlyphInfo? {
        if let info = glyphMap[char] { return info }
        return addGlyph(char)
    }

    /// 指定された文字列の配置済みグリフ配列を生成します。
    ///
    /// - Parameter string: レイアウトするテキスト。
    /// - Returns: 配置済みグリフの配列。いずれかのグリフを解決できなかった場合は nil。
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

    /// 文字列の合計幅をピクセル単位で計算します。
    ///
    /// - Parameter string: 計測するテキスト。
    /// - Returns: 合計アドバンス幅。
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
        // Core Text 経由でグリフメトリクスを取得
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

        // アトラス内の配置位置を検索（シェルフパッキング）
        guard let (px, py) = findSpace(width: glyphW, height: glyphH) else { return nil }

        // グリフをビットマップにレンダリング
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

        // アトラステクスチャに書き込み
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
        // 既存のシェルフに収まるか確認
        for i in 0..<shelves.count {
            if shelves[i].height >= height && shelves[i].nextX + width <= atlasWidth {
                let pos = (shelves[i].nextX, shelves[i].y)
                shelves[i].nextX += width
                return pos
            }
        }

        // 新しいシェルフを作成
        if currentShelfY + height <= atlasHeight {
            let shelf = Shelf(y: currentShelfY, height: height, nextX: width)
            shelves.append(shelf)
            let pos = (0, currentShelfY)
            currentShelfY += height
            return pos
        }

        // アトラスを拡張
        if atlasHeight < Self.maxSize {
            let newHeight = min(atlasHeight * 2, Self.maxSize)
            if let newTex = createTexture(width: atlasWidth, height: newHeight) {
                // 既存データをコピー
                copyTexture(from: texture!, to: newTex, width: atlasWidth, height: atlasHeight)
                texture = newTex

                // UV座標を再計算（atlasHeight更新前にスケール）
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

                // 新しいシェルフでリトライ
                return findSpace(width: width, height: height)
            }
        }

        return nil  // アトラスが満杯
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
        // CPU 側コピー（マネージドストレージ）
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

/// Core Text を使用してテキストを MTLTexture にレンダリングし、LRU キャッシュを備えます。
@MainActor
final class TextRenderer {
    private let device: MTLDevice
    private var cache: [TextCacheKey: CachedText] = [:]
    var maxCacheSize: Int = 256

    /// フォントとサイズをキーとするグリフアトラスキャッシュ。
    private var atlases: [GlyphAtlas.Key: GlyphAtlas] = [:]

    struct TextCacheKey: Hashable {
        let string: String
        let fontSize: Float
        let fontFamily: String
        let maxWidth: Float
        let maxHeight: Float
        let leading: Float

        /// 単一行テキスト用のキャッシュキーを初期化します。
        init(string: String, fontSize: Float, fontFamily: String) {
            self.string = string
            self.fontSize = fontSize
            self.fontFamily = fontFamily
            self.maxWidth = 0
            self.maxHeight = 0
            self.leading = 0
        }

        /// 複数行テキスト用のキャッシュキーを初期化します。
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

    /// キャッシュからテキストテクスチャを取得するか、新しいものをレンダリングします。
    ///
    /// - Parameters:
    ///   - string: レンダリングするテキスト。
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名。
    ///   - frameCount: LRU トラッキング用の現在のフレーム番号。
    /// - Returns: キャッシュされたテキストエントリ。レンダリングに失敗した場合は nil。
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

    /// テキスト文字列の幅をレンダリングせずに計算します。
    ///
    /// - Parameters:
    ///   - string: 計測するテキスト。
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名。
    /// - Returns: ピクセル単位のテキスト幅。
    func textWidth(string: String, fontSize: Float, fontFamily: String) -> Float {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attrString = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        return Float(ceil(bounds.width))
    }

    /// フォントのアセント（ベースラインより上の高さ）を取得します。
    ///
    /// - Parameters:
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名。
    /// - Returns: ピクセル単位のアセント値。
    func textAscent(fontSize: Float, fontFamily: String) -> Float {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        return Float(CTFontGetAscent(font))
    }

    /// フォントのディセント（ベースラインより下の高さ、正の値）を取得します。
    ///
    /// - Parameters:
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名。
    /// - Returns: ピクセル単位のディセント値。
    func textDescent(fontSize: Float, fontFamily: String) -> Float {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        return Float(CTFontGetDescent(font))
    }

    /// キャッシュから複数行テキストテクスチャを取得するか、CTFramesetter を使用してワードラップ付きで新しくレンダリングします。
    ///
    /// - Parameters:
    ///   - string: レンダリングするテキスト。
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名。
    ///   - maxWidth: 行折り返しの最大幅。
    ///   - maxHeight: 最大高さ。0で無制限。
    ///   - leading: 行間隔の倍率。
    ///   - frameCount: LRU トラッキング用の現在のフレーム番号。
    /// - Returns: キャッシュされたテキストエントリ。レンダリングに失敗した場合は nil。
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

    /// 指定されたフォントのグリフアトラスを取得し、必要に応じて作成します。
    ///
    /// - Parameters:
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名。
    /// - Returns: 指定されたフォントとサイズのグリフアトラス。
    func getAtlas(fontSize: Float, fontFamily: String) -> GlyphAtlas {
        let key = GlyphAtlas.Key(fontFamily: fontFamily, fontSize: fontSize)
        if let atlas = atlases[key] { return atlas }
        let atlas = GlyphAtlas(device: device, fontFamily: fontFamily, fontSize: fontSize)
        atlases[key] = atlas
        return atlas
    }

    /// 指定された文字列のアトラスから配置済みグリフを取得します。
    ///
    /// - Parameters:
    ///   - string: レイアウトするテキスト。
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名。
    /// - Returns: アトラステクスチャと配置済みグリフのタプル。いずれかのグリフがアトラスに収まらない場合は nil。
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

        // CGBitmapContext（RGBA プリマルチプライド）
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

        // 透明な背景に白いテキストを描画
        ctx.setTextDrawingMode(.fill)
        let originX = -bounds.origin.x + 2
        let originY = -bounds.origin.y + 2
        ctx.textPosition = CGPoint(x: originX, y: originY)
        CTLineDraw(line, ctx)

        // MTLTexture にアップロード
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

        // 段落スタイル（行間隔）
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(fontSize) * CGFloat(leading - 1.0)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: PlatformColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let attrString = NSAttributedString(string: string, attributes: attributes)

        // CTFramesetter でレイアウト
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

        // CGBitmapContext（RGBA プリマルチプライド）
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

        // CoreText はボトムレフト原点を使用。CGBitmapContext もボトムレフト原点。
        // ただしテクスチャはトップレフト原点なので、描画前に垂直反転。
        ctx.translateBy(x: 0, y: CGFloat(texHeight))
        ctx.scaleBy(x: 1.0, y: -1.0)

        // テキストフレームを作成して描画
        let framePath = CGPath(
            rect: CGRect(x: 2, y: 2, width: texWidth - 4, height: texHeight - 4),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), framePath, nil
        )
        CTFrameDraw(frame, ctx)

        // MTLTexture にアップロード
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
