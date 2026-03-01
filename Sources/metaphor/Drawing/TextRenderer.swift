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

// MARK: - TextRenderer

/// Core Text を使ってテキストを MTLTexture にレンダリングし、LRU キャッシュするクラス
@MainActor
final class TextRenderer {
    private let device: MTLDevice
    private var cache: [TextCacheKey: CachedText] = [:]
    private let maxCacheSize: Int = 256

    struct TextCacheKey: Hashable {
        let string: String
        let fontSize: Float
        let fontFamily: String
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

    private func evictOldest() {
        let sorted = cache.sorted { $0.value.lastUsedFrame < $1.value.lastUsedFrame }
        let removeCount = cache.count - maxCacheSize / 2
        for (key, _) in sorted.prefix(removeCount) {
            cache.removeValue(forKey: key)
        }
    }
}
