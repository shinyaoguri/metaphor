import Metal
import AppKit
import CoreText

// MARK: - Text Alignment

/// テキストの水平揃え
public enum TextAlignH: Sendable {
    case left, center, right
}

/// テキストの垂直揃え
public enum TextAlignV: Sendable {
    case top, center, baseline, bottom
}

// MARK: - Glyph Info

/// グリフアトラス内の1文字の情報
struct GlyphInfo {
    /// アトラス内の UV 座標 (0.0〜1.0)
    let u0: Float, v0: Float, u1: Float, v1: Float
    /// ピクセルサイズ
    let width: Float, height: Float
    /// ベースラインからの水平オフセット
    let bearingX: Float
    /// ベースラインからの垂直オフセット（上が正）
    let bearingY: Float
    /// 次の文字への水平距離
    let advance: Float
}

/// テキスト描画用の配置済みグリフ
struct PositionedGlyph {
    let x: Float, y: Float
    let width: Float, height: Float
    let u0: Float, v0: Float, u1: Float, v1: Float
}

// MARK: - Glyph Atlas

/// フォント＋サイズごとのグリフアトラス（Shelf Packing）
@MainActor
final class GlyphAtlas {

    /// アトラスキー（フォント名 + サイズ）
    struct Key: Hashable {
        let fontFamily: String
        let fontSize: Float
    }

    private let device: MTLDevice
    private let fontSize: Float
    private let fontFamily: String
    private let font: CTFont

    /// アトラステクスチャ
    private(set) var texture: MTLTexture?

    /// 現在のアトラスサイズ
    private var atlasWidth: Int
    private var atlasHeight: Int

    /// グリフマッピング
    private var glyphMap: [Character: GlyphInfo] = [:]

    /// Shelf packing 状態
    private var shelves: [Shelf] = []
    private var currentShelfY: Int = 0

    private struct Shelf {
        var y: Int
        var height: Int
        var nextX: Int
    }

    /// 最大テクスチャサイズ
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

    /// グリフ情報を取得（なければアトラスに追加）
    func glyph(for char: Character) -> GlyphInfo? {
        if let info = glyphMap[char] { return info }
        return addGlyph(char)
    }

    /// 文字列の配置済みグリフ列を生成
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

    /// 文字列の幅を計算
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
        // Core Text でグリフメトリクスを取得
        let str = String(char)
        let attrString = NSAttributedString(
            string: str,
            attributes: [.font: font, .foregroundColor: NSColor.white]
        )
        let line = CTLineCreateWithAttributedString(attrString)

        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let advance = Float(lineWidth)

        let glyphW = Int(ceil(lineWidth)) + 2
        let glyphH = Int(ceil(ascent + descent)) + 2
        guard glyphW > 0, glyphH > 0 else { return nil }

        // アトラス内の配置位置を見つける（shelf packing）
        guard let (px, py) = findSpace(width: glyphW, height: glyphH) else { return nil }

        // グリフをビットマップに描画
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
        // 既存の棚に収まるか
        for i in 0..<shelves.count {
            if shelves[i].height >= height && shelves[i].nextX + width <= atlasWidth {
                let pos = (shelves[i].nextX, shelves[i].y)
                shelves[i].nextX += width
                return pos
            }
        }

        // 新しい棚を作成
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
                atlasHeight = newHeight

                // UV を再計算
                var updated: [Character: GlyphInfo] = [:]
                for (char, old) in glyphMap {
                    let scale = Float(atlasHeight) / Float(newHeight)
                    updated[char] = GlyphInfo(
                        u0: old.u0, v0: old.v0 * scale,
                        u1: old.u1, v1: old.v1 * scale,
                        width: old.width, height: old.height,
                        bearingX: old.bearingX, bearingY: old.bearingY,
                        advance: old.advance
                    )
                }
                glyphMap = updated

                // 新しい棚で再試行
                return findSpace(width: width, height: height)
            }
        }

        return nil  // アトラスが一杯
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
        // CPU 側コピー（managed ストレージ）
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

/// Core Text を使ってテキストを MTLTexture にレンダリングし、LRU キャッシュするクラス
@MainActor
final class TextRenderer {
    private let device: MTLDevice
    private var cache: [TextCacheKey: CachedText] = [:]
    var maxCacheSize: Int = 256

    /// グリフアトラスキャッシュ（フォント＋サイズごと）
    private var atlases: [GlyphAtlas.Key: GlyphAtlas] = [:]

    struct TextCacheKey: Hashable {
        let string: String
        let fontSize: Float
        let fontFamily: String
        let maxWidth: Float
        let maxHeight: Float
        let leading: Float

        /// 単行テキスト用の簡易イニシャライザ
        init(string: String, fontSize: Float, fontFamily: String) {
            self.string = string
            self.fontSize = fontSize
            self.fontFamily = fontFamily
            self.maxWidth = 0
            self.maxHeight = 0
            self.leading = 0
        }

        /// 複数行テキスト用イニシャライザ
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

    /// テキストをテクスチャとして取得（キャッシュヒットまたは新規生成）
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

    /// テキストの幅を計算（描画せずにサイズだけ取得）
    func textWidth(string: String, fontSize: Float, fontFamily: String) -> Float {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attrString = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        return Float(ceil(bounds.width))
    }

    /// フォントのアセントを取得（ベースラインより上の高さ）
    func textAscent(fontSize: Float, fontFamily: String) -> Float {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        return Float(CTFontGetAscent(font))
    }

    /// フォントのディセントを取得（ベースラインより下の高さ、正の値）
    func textDescent(fontSize: Float, fontFamily: String) -> Float {
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        return Float(CTFontGetDescent(font))
    }

    /// 複数行テキストをテクスチャとして取得（CTFramesetterで折り返し）
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

    /// グリフアトラスを取得（なければ作成）
    func getAtlas(fontSize: Float, fontFamily: String) -> GlyphAtlas {
        let key = GlyphAtlas.Key(fontFamily: fontFamily, fontSize: fontSize)
        if let atlas = atlases[key] { return atlas }
        let atlas = GlyphAtlas(device: device, fontFamily: fontFamily, fontSize: fontSize)
        atlases[key] = atlas
        return atlas
    }

    /// アトラスから文字列の配置済みグリフを取得
    /// 全文字がアトラスに収まらない場合は nil を返す
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
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let texWidth = Int(ceil(bounds.width)) + 4
        let texHeight = Int(ceil(bounds.height)) + 4
        guard texWidth > 0, texHeight > 0 else { return nil }

        // CGBitmapContext（RGBA premultiplied）
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

        // 白テキストを透明背景に描画
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

        // 段落スタイル（行間）
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(fontSize) * CGFloat(leading - 1.0)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let attrString = NSAttributedString(string: string, attributes: attributes)

        // CTFramesetterでレイアウト
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

        // CGBitmapContext（RGBA premultiplied）
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

        // CoreTextは左下原点。CGBitmapContextも左下原点なのでそのまま描画。
        // ただしテクスチャは左上原点なので、上下反転して描画する。
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
