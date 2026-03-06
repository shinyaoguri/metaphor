import CoreML
import CoreVideo
import Metal

/// Provide conversion utilities between MTLTexture, CVPixelBuffer, and CGImage.
///
/// Use this converter for CoreML/Vision input and output texture conversion.
/// The output path (CVPixelBuffer to MTLTexture) uses the same zero-copy
/// CVMetalTextureCache approach as CaptureDevice.
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
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif
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

    /// Convert an MTLTexture to a CVPixelBuffer using a copy-based approach.
    /// - Parameter texture: The input texture (bgra8Unorm).
    /// - Returns: A CVPixelBuffer in kCVPixelFormatType_32BGRA format, or nil on failure.
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

    /// Convert a CVPixelBuffer to an MTLTexture using zero-copy Metal texture caching.
    /// - Parameter pixelBuffer: The input pixel buffer.
    /// - Returns: An MTLTexture in bgra8Unorm format, or nil on failure.
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

    /// Convert a CGImage to an MTLTexture.
    /// - Parameter cgImage: The input Core Graphics image.
    /// - Returns: An MTLTexture in bgra8Unorm format, or nil on failure.
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

    /// Convert an MTLTexture to a CGImage.
    /// - Parameter texture: The input Metal texture.
    /// - Returns: A CGImage, or nil on failure.
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

    /// Convert a 2D MLMultiArray (grayscale) to an MTLTexture.
    /// - Parameters:
    ///   - multiArray: The input array (shape: [1, height, width] or [height, width]).
    ///   - normalize: When true, apply min-max normalization to the data.
    /// - Returns: A bgra8Unorm texture with the grayscale value replicated across all RGB channels.
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
