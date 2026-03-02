import CoreML
import CoreVideo
import Metal

/// MTLTexture <-> CVPixelBuffer <-> CGImage 変換ユーティリティ
///
/// CoreML/Vision の入力/出力テクスチャ変換に使用する。
/// 出力パス（CVPixelBuffer → MTLTexture）は CaptureDevice と同じ
/// CVMetalTextureCache ゼロコピー方式を使用。
@MainActor
public final class MLTextureConverter {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
        setupTextureCache()
    }

    private func setupTextureCache() {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    // MARK: - MTLTexture -> CVPixelBuffer

    /// MTLTexture を CVPixelBuffer に変換（コピーベース）
    /// - Parameter texture: 入力テクスチャ (bgra8Unorm)
    /// - Returns: CVPixelBuffer (kCVPixelFormatType_32BGRA)
    public func pixelBuffer(from texture: MTLTexture) -> CVPixelBuffer? {
        let width = texture.width
        let height = texture.height

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            nil, width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        if texture.storageMode == .private {
            // Private storage: blit で managed ステージングテクスチャにコピー
            guard let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            #if os(macOS)
            desc.storageMode = .managed
            #else
            desc.storageMode = .shared
            #endif
            desc.usage = .shaderRead
            guard let staging = device.makeTexture(descriptor: desc),
                  let blit = cmdBuf.makeBlitCommandEncoder() else { return nil }
            blit.copy(from: texture, to: staging)
            #if os(macOS)
            blit.synchronize(resource: staging)
            #endif
            blit.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            staging.getBytes(baseAddress, bytesPerRow: bytesPerRow,
                           from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        } else {
            texture.getBytes(baseAddress, bytesPerRow: bytesPerRow,
                           from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }

        return buffer
    }

    // MARK: - CVPixelBuffer -> MTLTexture (zero-copy)

    /// CVPixelBuffer を MTLTexture にゼロコピー変換
    /// - Parameter pixelBuffer: 入力ピクセルバッファ
    /// - Returns: MTLTexture (bgra8Unorm)
    public func texture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTex = cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTex)
    }

    // MARK: - CGImage -> MTLTexture

    /// CGImage を MTLTexture に変換
    public func texture(from cgImage: CGImage) -> MTLTexture? {
        let width = cgImage.width
        let height = cgImage.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        tex.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: bytesPerRow
        )
        return tex
    }

    // MARK: - MTLTexture -> CGImage

    /// MTLTexture を CGImage に変換
    public func cgImage(from texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        if texture.storageMode == .private {
            guard let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            #if os(macOS)
            desc.storageMode = .managed
            #else
            desc.storageMode = .shared
            #endif
            desc.usage = .shaderRead
            guard let staging = device.makeTexture(descriptor: desc),
                  let blit = cmdBuf.makeBlitCommandEncoder() else { return nil }
            blit.copy(from: texture, to: staging)
            #if os(macOS)
            blit.synchronize(resource: staging)
            #endif
            blit.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            staging.getBytes(&pixels, bytesPerRow: bytesPerRow,
                           from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        } else {
            texture.getBytes(&pixels, bytesPerRow: bytesPerRow,
                           from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }

        // BGRA → RGBA
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = pixels[i]
            pixels[i] = pixels[i + 2]
            pixels[i + 2] = b
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        return context.makeImage()
    }

    // MARK: - MLMultiArray -> MTLTexture

    /// 2D MLMultiArray（グレースケール）を MTLTexture に変換
    /// - Parameters:
    ///   - multiArray: 入力 (shape: [1, height, width] or [height, width])
    ///   - normalize: true の場合 min-max 正規化
    /// - Returns: bgra8Unorm テクスチャ（グレースケール値を全 RGB チャンネルに展開）
    public func texture(from multiArray: MLMultiArray, normalize: Bool = true) -> MTLTexture? {
        let shape = multiArray.shape.map { $0.intValue }
        let width: Int
        let height: Int

        if shape.count == 3 {
            height = shape[1]
            width = shape[2]
        } else if shape.count == 2 {
            height = shape[0]
            width = shape[1]
        } else {
            return nil
        }

        let count = width * height
        var floatData = [Float](repeating: 0, count: count)
        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            floatData[i] = ptr[i]
        }

        if normalize {
            let minVal = floatData.min() ?? 0
            let maxVal = floatData.max() ?? 1
            let range = maxVal - minVal
            if range > 0 {
                for i in 0..<count {
                    floatData[i] = (floatData[i] - minVal) / range
                }
            }
        }

        // Float → BGRA8
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<count {
            let v = UInt8(max(0, min(255, floatData[i] * 255)))
            let j = i * 4
            pixels[j] = v     // B
            pixels[j + 1] = v // G
            pixels[j + 2] = v // R
            pixels[j + 3] = 255 // A
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        tex.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
        return tex
    }
}
