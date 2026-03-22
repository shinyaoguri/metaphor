import CoreML
import CoreVideo
import Metal

/// MTLTexture、CVPixelBuffer、CGImage 間の変換ユーティリティを提供します。
///
/// CoreML/Vision の入出力テクスチャ変換に使用します。
/// 出力パス（CVPixelBuffer → MTLTexture）は CaptureDevice と同じ
/// ゼロコピーの CVMetalTextureCache アプローチを使用します。
@MainActor
public final class MLTextureConverter {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var stagingTextureCache: MTLTexture?
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0

    public init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
        setupTextureCache()
    }

    private func setupTextureCache() {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    private func getOrCreateStagingTexture(width: Int, height: Int) -> MTLTexture? {
        if let existing = stagingTextureCache,
           existing.width == width, existing.height == height {
            return existing
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.storageMode = .shared
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        stagingTextureCache = tex
        return tex
    }

    private func getOrCreatePixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        if let pool = pixelBufferPool, poolWidth == width, poolHeight == height {
            return pool
        }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        pixelBufferPool = pool
        poolWidth = width
        poolHeight = height
        return pool
    }

    // MARK: - MTLTexture -> CVPixelBuffer

    /// MTLTexture をコピーベースのアプローチで CVPixelBuffer に変換します。
    /// - Parameter texture: 入力テクスチャ（bgra8Unorm）。
    /// - Returns: kCVPixelFormatType_32BGRA 形式の CVPixelBuffer。失敗時は nil。
    public func pixelBuffer(from texture: MTLTexture) -> CVPixelBuffer? {
        let width = texture.width
        let height = texture.height

        guard let pool = getOrCreatePixelBufferPool(width: width, height: height) else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        if texture.storageMode == .private {
            guard let staging = getOrCreateStagingTexture(width: width, height: height),
                  let cmdBuf = commandQueue.makeCommandBuffer(),
                  let blit = cmdBuf.makeBlitCommandEncoder() else { return nil }
            blit.copy(from: texture, to: staging)
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

    // MARK: - CVPixelBuffer -> MTLTexture（ゼロコピー）

    /// CVPixelBuffer をゼロコピーの Metal テクスチャキャッシュを使用して MTLTexture に変換します。
    /// - Parameter pixelBuffer: 入力ピクセルバッファ。
    /// - Returns: bgra8Unorm 形式の MTLTexture。失敗時は nil。
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

    /// CGImage を MTLTexture に変換します。
    /// - Parameter cgImage: 入力 Core Graphics 画像。
    /// - Returns: bgra8Unorm 形式の MTLTexture。失敗時は nil。
    public func texture(from cgImage: CGImage) -> MTLTexture? {
        let width = cgImage.width
        let height = cgImage.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
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

    /// MTLTexture を CGImage に変換します。
    /// - Parameter texture: 入力 Metal テクスチャ。
    /// - Returns: CGImage。失敗時は nil。
    public func cgImage(from texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        if texture.storageMode == .private {
            guard let staging = getOrCreateStagingTexture(width: width, height: height),
                  let cmdBuf = commandQueue.makeCommandBuffer(),
                  let blit = cmdBuf.makeBlitCommandEncoder() else { return nil }
            blit.copy(from: texture, to: staging)
            blit.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            staging.getBytes(&pixels, bytesPerRow: bytesPerRow,
                           from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        } else {
            texture.getBytes(&pixels, bytesPerRow: bytesPerRow,
                           from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        return context.makeImage()
    }

    // MARK: - MLMultiArray -> MTLTexture

    /// 2D MLMultiArray（グレースケール）を MTLTexture に変換します。
    /// - Parameters:
    ///   - multiArray: 入力配列（形状: [1, height, width] または [height, width]）。
    ///   - normalize: true の場合、データに最小-最大正規化を適用します。
    /// - Returns: グレースケール値を全 RGB チャンネルに複製した bgra8Unorm テクスチャ。
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

        switch multiArray.dataType {
        case .float32:
            let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: count)
            for i in 0..<count {
                floatData[i] = ptr[i]
            }
        case .double:
            let ptr = multiArray.dataPointer.bindMemory(to: Double.self, capacity: count)
            for i in 0..<count {
                floatData[i] = Float(ptr[i])
            }
        case .int32:
            let ptr = multiArray.dataPointer.bindMemory(to: Int32.self, capacity: count)
            for i in 0..<count {
                floatData[i] = Float(ptr[i])
            }
        case .float16:
            let ptr = multiArray.dataPointer.bindMemory(to: Float16.self, capacity: count)
            for i in 0..<count {
                floatData[i] = Float(ptr[i])
            }
        default:
            // MLMultiArrayDataType.int8 (rawValue 131080) は macOS 26.0+ SDK でのみ利用可能なため、
            // 古い SDK でのコンパイルエラーを避けるために rawValue で比較します。
            if multiArray.dataType.rawValue == 131080 {
                let ptr = multiArray.dataPointer.bindMemory(to: Int8.self, capacity: count)
                for i in 0..<count {
                    floatData[i] = Float(ptr[i])
                }
            } else {
                print("[metaphor] Unsupported MLMultiArray dataType: \(multiArray.dataType.rawValue)")
                return nil
            }
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

        // Float -> BGRA8
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
        desc.storageMode = .shared
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
