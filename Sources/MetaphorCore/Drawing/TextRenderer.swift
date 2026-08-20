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

// MARK: - Text Metrics

/// 1 文字ぶんのタイポグラフィック計測を 1 か所に集めます。
///
/// 測る側（``TextRenderer/textWidth(string:fontSize:fontFamily:)``）と描く側
/// （``GlyphAtlas``）で物差しがずれないよう、advance はここでしか計算しません（#802）。
///
/// 文字列全体をシェーピングすると隣り合う字のカーニングが入りますが、`text()` の描画は
/// 1 文字ずつ置くので、計測も 1 文字ずつ行います。こうすると幅が加法的になり
/// （`textWidth("ab") == textWidth("a") + textWidth("b")`）、語ごとに測って組版できます。
enum TextMetrics {

    /// 1 文字ぶんの計測結果。`line` は描画にも使えます（同じシェーピング結果を共有するため）。
    struct CharMetrics {
        let line: CTLine
        let advance: Float
        let ascent: CGFloat
        let descent: CGFloat
    }

    /// 1 文字を単独でシェーピングして計測します。
    ///
    /// - Parameters:
    ///   - char: 計測する文字。
    ///   - font: 計測に使うフォント。
    ///   - attributes: 追加の属性（描画に使う `line` が要るときの前景色など）。
    /// - Returns: advance とベースライン基準の高さ、およびそれらを得た `CTLine`。
    static func measure(
        _ char: Character, font: CTFont, attributes: [NSAttributedString.Key: Any] = [:]
    ) -> CharMetrics {
        var attributes = attributes
        attributes[.font] = font
        let attrString = NSAttributedString(string: String(char), attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)

        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let advance = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return CharMetrics(line: line, advance: Float(advance), ascent: ascent, descent: descent)
    }
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
        // 先に全文字のグリフを解決してアトラス寸法を確定させる。配置しながら
        // 解決すると、途中の addGlyph がアトラスを縦拡張したときに積み終えた
        // PositionedGlyph の v0/v1 が旧高さ基準のまま残り、文字列の前半が潰れる。
        // （拡張時は glyphMap 側の UV が再スケールされるため、解決を終えてから
        // glyphMap を読めば常に最新のアトラス基準になる。）
        for char in string {
            guard glyph(for: char) != nil else { return nil }
        }

        var result: [PositionedGlyph] = []
        result.reserveCapacity(string.count)
        var cursorX: Float = 0

        for char in string {
            guard let g = glyphMap[char] else { return nil }
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
        // Core Text 経由でグリフメトリクスを取得（textWidth と同じ物差しを使う）
        let metrics = TextMetrics.measure(
            char, font: font, attributes: [.foregroundColor: PlatformColor.white])
        let line = metrics.line
        let ascent = metrics.ascent
        let descent = metrics.descent
        let advance = metrics.advance

        let glyphW = Int(ceil(CGFloat(advance))) + 2
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
            // ビットマップは左右に 1px の余白を持つ（textPosition.x = 1）。その 1px を
            // 引かないと、文字が送り位置より 1px 右へずれて描かれる — 縦は bearingY が
            // 同じ 1px を織り込み済み。これで advance の箱を左右対称にはみ出す形になる。
            bearingX: -1,
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

    /// アトラス数の上限。`textSize()` を連続変化させるスケッチで 512×512〜512×2048 の
    /// テクスチャが無制限に蓄積しないよう、超過時は最も使われていないものを追い出す。
    var maxAtlases: Int = 8

    /// アトラスの LRU 追跡（アクセスごとに単調増加するカウンターを記録）。
    private var atlasUseCounter: Int = 0
    private var atlasLastUse: [GlyphAtlas.Key: Int] = [:]

    /// `CTFontCreateWithName` の結果キャッシュ。
    /// textWidth/textAscent/textDescent が呼び出しごと（text() 1 回につき 2 回）に
    /// フォントを生成していたコストを回収する。
    private var fontCache: [GlyphAtlas.Key: CTFont] = [:]

    /// 1 文字ぶんの advance のキャッシュキー。
    private struct AdvanceKey: Hashable {
        let fontFamily: String
        let fontSize: Float
        let char: Character
    }

    /// `textWidth` が使う 1 文字ぶんの advance キャッシュ。
    private var advanceCache: [AdvanceKey: Float] = [:]

    /// テスト用: 現在保持しているアトラス数。
    var atlasCount: Int { atlases.count }

    /// キャッシュ経由で CTFont を取得します。
    private func cachedFont(fontSize: Float, fontFamily: String) -> CTFont {
        let key = GlyphAtlas.Key(fontFamily: fontFamily, fontSize: fontSize)
        if let font = fontCache[key] { return font }
        let font = CTFontCreateWithName(fontFamily as CFString, CGFloat(fontSize), nil)
        // フォントサイズアニメーション等でのキー増殖を防ぐ（CTFont は軽量なので単純リセット）
        if fontCache.count >= 64 {
            fontCache.removeAll()
        }
        fontCache[key] = font
        return font
    }

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

    /// レンダリング済みテキストテクスチャとグリフアトラスを全削除します。
    ///
    /// メモリを回収したいシーン切替時などに呼び出してください。次回テキスト描画時に
    /// アトラスとキャッシュは自動的に再構築されます。
    func clearCache() {
        cache.removeAll()
        atlases.removeAll()
        atlasLastUse.removeAll()
        fontCache.removeAll()
        advanceCache.removeAll()
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
    /// 1 文字ずつの advance を足した値で、`GlyphAtlas` がグリフを置くときの送り量と
    /// 同じ物差しです（#802）。切り上げず、末尾の空白も数えます。
    ///
    /// - Parameters:
    ///   - string: 計測するテキスト。
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名。
    /// - Returns: ピクセル単位のテキスト幅。
    func textWidth(string: String, fontSize: Float, fontFamily: String) -> Float {
        guard !string.isEmpty else { return 0 }
        let font = cachedFont(fontSize: fontSize, fontFamily: fontFamily)
        var width: Float = 0
        for char in string {
            width += advance(of: char, font: font, fontSize: fontSize, fontFamily: fontFamily)
        }
        return width
    }

    /// キャッシュ経由で 1 文字ぶんの advance を取得します。
    ///
    /// 1 文字ごとに `CTLine` を作るので、キャッシュが無いと文字数ぶんのシェーピングが
    /// 毎フレーム走ります（`textWidth()` は行の配置計算で毎フレーム呼ばれます）。
    private func advance(
        of char: Character, font: CTFont, fontSize: Float, fontFamily: String
    ) -> Float {
        let key = AdvanceKey(fontFamily: fontFamily, fontSize: fontSize, char: char)
        if let cached = advanceCache[key] { return cached }
        let advance = TextMetrics.measure(char, font: font).advance
        // フォントサイズアニメーション等でのキー増殖を防ぐ（cachedFont と同じ扱い）
        if advanceCache.count >= 4096 {
            advanceCache.removeAll()
        }
        advanceCache[key] = advance
        return advance
    }

    /// フォントのアセント（ベースラインより上の高さ）を取得します。
    ///
    /// - Parameters:
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名。
    /// - Returns: ピクセル単位のアセント値。
    func textAscent(fontSize: Float, fontFamily: String) -> Float {
        let font = cachedFont(fontSize: fontSize, fontFamily: fontFamily)
        return Float(CTFontGetAscent(font))
    }

    /// フォントのディセント（ベースラインより下の高さ、正の値）を取得します。
    ///
    /// - Parameters:
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名。
    /// - Returns: ピクセル単位のディセント値。
    func textDescent(fontSize: Float, fontFamily: String) -> Float {
        let font = cachedFont(fontSize: fontSize, fontFamily: fontFamily)
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
    ///   - leading: 行の高さ（ピクセル単位）。
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
        atlasUseCounter += 1
        if let atlas = atlases[key] {
            atlasLastUse[key] = atlasUseCounter
            return atlas
        }
        // 上限到達時は最も使われていないアトラスを追い出す
        // （テクスチャは in-flight コマンドバッファが参照中でも Metal 側で保持される）
        if atlases.count >= maxAtlases,
           let evictKey = atlasLastUse.min(by: { $0.value < $1.value })?.key {
            atlases.removeValue(forKey: evictKey)
            atlasLastUse.removeValue(forKey: evictKey)
        }
        let atlas = GlyphAtlas(device: device, fontFamily: fontFamily, fontSize: fontSize)
        atlases[key] = atlas
        atlasLastUse[key] = atlasUseCounter
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

    // MARK: - Outline API

    /// 文字列のグリフアウトラインを、輪郭ごとの閉じたポリラインとして返します。
    ///
    /// 座標は**ベースライン左端が原点**で、y は metaphor の 2D 座標系に合わせて下向き
    /// （Core Text のグリフパスは y 上向きなので反転している）。各ポリラインは終点に
    /// 始点を重ねません（閉じているものとして扱ってください）。
    ///
    /// 文字の穴（`o` の内側など）も 1 本の輪郭として返ります。どれが穴かは呼び出し側で
    /// 包含関係から判定します — TrueType と CFF で外周の巻き方向の慣習が逆で、
    /// 巻き方向からは決められないためです。
    ///
    /// 字送りは ``GlyphAtlas/layoutGlyphs(string:)`` と同じく **1 文字ずつ
    /// ``TextMetrics/measure(_:font:attributes:)`` の advance** で進めます。文字列全体を
    /// 1 本の `CTLine` に通すとカーニングが入って `text()` の描画と字間がずれるためです
    /// （#821）。その代わり、**複数文字にまたがるシェーピング（リガチャ、アラビア文字の
    /// 連結形、インド系文字の並べ替え）は掛かりません** — 1 文字ぶんのシェーピング結果を
    /// 順に置いた輪郭になります。これは `text()` の描画と `textWidth()` の加法性
    /// （`textWidth("ab") == textWidth("a") + textWidth("b")`、#802）に合わせた選択で、
    /// Processing がカーニングを掛けないのとも揃っています。フォントに無い文字の
    /// フォールバックは 1 文字ぶんの `CTLine` が解決するので従来どおり効きます。
    ///
    /// - Parameters:
    ///   - string: アウトラインを取り出すテキスト。
    ///   - fontSize: ポイント単位のフォントサイズ。
    ///   - fontFamily: フォントファミリー名（`MFont` の PostScript 名も可）。
    ///   - sampleFactor: 曲線を折れ線へ分割する細かさ。大きいほど点が増えます。
    /// - Returns: 輪郭ごとのポリラインの配列。
    func glyphContours(
        string: String, fontSize: Float, fontFamily: String, sampleFactor: Float
    ) -> [[Vec2]] {
        guard !string.isEmpty else { return [] }
        let font = cachedFont(fontSize: fontSize, fontFamily: fontFamily)

        var result: [[Vec2]] = []
        var cursorX: CGFloat = 0
        for char in string {
            // 描く側と同じ物差しで送る。1 文字ずつ測るので隣の字のカーニングが入らない。
            let metrics = TextMetrics.measure(char, font: font)
            appendContours(
                of: metrics.line, fallbackFont: font, cursorX: cursorX,
                sampleFactor: sampleFactor, into: &result)
            cursorX += CGFloat(metrics.advance)
        }
        return result
    }

    /// 1 文字ぶんの `CTLine` からグリフ輪郭を取り出し、`cursorX` へ寄せて積みます。
    private func appendContours(
        of line: CTLine, fallbackFont: CTFont, cursorX: CGFloat,
        sampleFactor: Float, into result: inout [[Vec2]]
    ) {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return }
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            // run ごとにフォントが違いうる（要求フォントに無い文字はフォールバックへ回る）
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName as String] as! CTFont? ?? fallbackFont

            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            let range = CFRange(location: 0, length: count)
            CTRunGetGlyphs(run, range, &glyphs)
            CTRunGetPositions(run, range, &positions)

            for i in 0..<count {
                guard let path = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else {
                    continue  // 空白など輪郭を持たないグリフ
                }
                // 1 文字が複数グリフ（結合文字など）でも、その中の相対位置は活かす
                let offset = CGPoint(x: cursorX + positions[i].x, y: positions[i].y)
                result.append(contentsOf: Self.flatten(
                    path: path, offset: offset, sampleFactor: sampleFactor))
            }
        }
    }

    /// `CGPath` を輪郭ごとの折れ線へ変換します（`offset` 平行移動 + y 反転こみ）。
    private static func flatten(
        path: CGPath, offset: CGPoint, sampleFactor: Float
    ) -> [[Vec2]] {
        // applyWithBlock のブロックはエスケープ扱いのため、状態はクラスに逃がす
        final class State {
            var contours: [[Vec2]] = []
            var current: [Vec2] = []
            var cursor: CGPoint = .zero
            var start: CGPoint = .zero
        }
        let state = State()

        func map(_ p: CGPoint) -> Vec2 {
            Vec2(Float(offset.x + p.x), Float(-(offset.y + p.y)))
        }
        // 制御点を結んだ折れ線の長さから分割数を決める（曲率が強いほど点が増える）
        // 式を細かく分けているのは Swift 5.10 の型チェッカ対策（#650）。
        func segmentCount(_ points: [CGPoint]) -> Int {
            var length: CGFloat = 0
            for i in 1..<points.count {
                let dx: CGFloat = points[i].x - points[i - 1].x
                let dy: CGFloat = points[i].y - points[i - 1].y
                length += (dx * dx + dy * dy).squareRoot()
            }
            let scaled: CGFloat = length * CGFloat(sampleFactor)
            let count = Int(scaled.rounded(.up))
            return min(64, max(2, count))
        }
        func flushContour() {
            if state.current.count > 2 { state.contours.append(state.current) }
            state.current = []
        }

        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                flushContour()
                state.cursor = element.points[0]
                state.start = state.cursor
                state.current.append(map(state.cursor))

            case .addLineToPoint:
                state.cursor = element.points[0]
                state.current.append(map(state.cursor))

            case .addQuadCurveToPoint:
                let control = element.points[0], end = element.points[1]
                let start = state.cursor
                let n = segmentCount([start, control, end])
                for step in 1...n {
                    let t: CGFloat = CGFloat(step) / CGFloat(n)
                    let u: CGFloat = 1 - t
                    // 重みを先に畳む（1 行に詰めると Swift 5.10 の型チェッカが落ちる）
                    let w0: CGFloat = u * u
                    let w1: CGFloat = 2 * u * t
                    let w2: CGFloat = t * t
                    let px: CGFloat = w0 * start.x + w1 * control.x + w2 * end.x
                    let py: CGFloat = w0 * start.y + w1 * control.y + w2 * end.y
                    state.current.append(map(CGPoint(x: px, y: py)))
                }
                state.cursor = end

            case .addCurveToPoint:
                let c1 = element.points[0], c2 = element.points[1], end = element.points[2]
                let start = state.cursor
                let n = segmentCount([start, c1, c2, end])
                for step in 1...n {
                    let t: CGFloat = CGFloat(step) / CGFloat(n)
                    let u: CGFloat = 1 - t
                    let w0: CGFloat = u * u * u
                    let w1: CGFloat = 3 * u * u * t
                    let w2: CGFloat = 3 * u * t * t
                    let w3: CGFloat = t * t * t
                    let px: CGFloat = w0 * start.x + w1 * c1.x + w2 * c2.x + w3 * end.x
                    let py: CGFloat = w0 * start.y + w1 * c1.y + w2 * c2.y + w3 * end.y
                    state.current.append(map(CGPoint(x: px, y: py)))
                }
                state.cursor = end

            case .closeSubpath:
                // 閉じた輪郭として扱うので始点を重ねて追加しない
                flushContour()
                state.cursor = state.start

            @unknown default:
                break
            }
        }
        flushContour()
        return state.contours
    }

    // MARK: - Private

    private func renderText(string: String, fontSize: Float, fontFamily: String) -> CachedText? {
        let font = cachedFont(fontSize: fontSize, fontFamily: fontFamily)
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
        let font = cachedFont(fontSize: fontSize, fontFamily: fontFamily)

        // 段落スタイル（行の高さ）。leading はピクセル単位の行の高さなので、最小と最大を
        // 揃えて固定する（lineSpacing で「足す」形だと、leading が自然な行高より小さい
        // ときに詰められず、3 引数版の text() と行ピッチがずれる）。
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = CGFloat(leading)
        paragraphStyle.maximumLineHeight = CGFloat(leading)

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

        // ここで垂直反転してはいけない（#504）。CGBitmapContext の座標系はボトム
        // レフト原点だが、バイト列は先頭行が画像の上端。CTFrameDraw をそのまま
        // 描けば、出来上がったバイト列は既にトップレフト原点の絵になっている。
        // 反転を挟むと二重にかかり、文字が上下反転・行順も逆になる（単一行の
        // renderText とグリフアトラスも反転を挟まない — 経路間で揃える）。

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
