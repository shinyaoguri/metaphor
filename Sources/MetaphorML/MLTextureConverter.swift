import CoreML
import MetaphorLog
import CoreVideo
import Metal
import ObjectiveC.runtime

/// Provides conversion utilities between `MTLTexture`, `CVPixelBuffer`, and `CGImage`.
///
/// Used for converting CoreML/Vision input and output textures. The output
/// path (`CVPixelBuffer` → `MTLTexture`) uses the same zero-copy
/// `CVMetalTextureCache` approach as `CaptureDevice`.
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

    /// Converts an `MTLTexture` to a `CVPixelBuffer` using a copy-based approach.
    ///
    /// - Important: For textures with `.private` storage, this **synchronously
    ///   waits** for the GPU copy to complete (`waitUntilCompleted`). Calling
    ///   this every frame inside `draw()` will cause dropped frames.
    /// - Parameter texture: The input texture (only `bgra8Unorm` is supported).
    /// - Returns: A `CVPixelBuffer` in `kCVPixelFormatType_32BGRA` format, or nil on failure.
    public func pixelBuffer(from texture: MTLTexture) -> CVPixelBuffer? {
        // BGRA8 前提のバイトコピーのため、他フォーマットは silent な
        // チャンネル化けになる前に弾く
        guard texture.pixelFormat == .bgra8Unorm else {
            metaphorWarning("MLTextureConverter.pixelBuffer(from:) requires bgra8Unorm, got \(texture.pixelFormat.rawValue)")
            return nil
        }
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

    /// Converts a `CVPixelBuffer` to an `MTLTexture` using a zero-copy Metal texture cache.
    /// - Parameter pixelBuffer: The input pixel buffer.
    /// - Returns: An `MTLTexture` in `bgra8Unorm` format, or nil on failure.
    public func texture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        // 使い終わったキャッシュエントリの内部リソースを回収する。CoreVideo の
        // ドキュメント上、テクスチャキャッシュは定期的な flush を必要とする。
        // 参照が残っている使用中のテクスチャには影響しない。
        CVMetalTextureCacheFlush(cache, 0)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess,
              let cvTex = cvTexture,
              let baseTexture = CVMetalTextureGetTexture(cvTex),
              let mtlTexture = baseTexture.makeTextureView(pixelFormat: baseTexture.pixelFormat)
        else { return nil }

        // CoreVideo の契約上、`CVMetalTextureGetTexture` が返す MTLTexture は
        // ラッパー（cvTex）が生存している間のみ有効。そこでラッパーを返り値の
        // テクスチャに関連付けて同じ寿命で生かし続ける。ただしラッパーは内部で
        // baseTexture を retain しているため、baseTexture へ直接関連付けると
        // 循環参照（baseTexture ⇄ cvTex）になり両者とも永遠に解放されない。
        // 同じストレージを指す texture view を作って返し、view 側へ関連付ける
        // ことで参照を一方向（view → cvTex → baseTexture）に保つ。
        objc_setAssociatedObject(
            mtlTexture, Self.cvTextureAssociationKey, cvTex, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return mtlTexture
    }

    /// A stable, unique key used by ``texture(from:)`` to associate the
    /// `CVMetalTexture` wrapper with the zero-copy texture.
    private static let cvTextureAssociationKey = UnsafeRawPointer(
        UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    )

    // MARK: - CGImage -> MTLTexture

    /// Converts a `CGImage` to an `MTLTexture`.
    /// - Parameter cgImage: The input Core Graphics image.
    /// - Returns: An `MTLTexture` in `bgra8Unorm` format, or nil on failure.
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

    /// Converts an `MTLTexture` to a `CGImage`.
    ///
    /// - Important: For textures with `.private` storage, this **synchronously
    ///   waits** for the GPU copy to complete (`waitUntilCompleted`). Calling
    ///   this every frame inside `draw()` will cause dropped frames.
    /// - Parameter texture: The input Metal texture (only `bgra8Unorm` is supported).
    /// - Returns: A `CGImage`, or nil on failure.
    public func cgImage(from texture: MTLTexture) -> CGImage? {
        // BGRA8 前提のバイトコピーのため、他フォーマットは silent な
        // チャンネル化けになる前に弾く
        guard texture.pixelFormat == .bgra8Unorm else {
            metaphorWarning("MLTextureConverter.cgImage(from:) requires bgra8Unorm, got \(texture.pixelFormat.rawValue)")
            return nil
        }
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

    /// Converts a 2D `MLMultiArray` (grayscale) to an `MTLTexture`.
    /// - Parameters:
    ///   - multiArray: The input array (shape: `[1, height, width]` or `[height, width]`).
    ///   - normalize: If true, applies min-max normalization to the data.
    /// - Returns: A `bgra8Unorm` texture with the grayscale value replicated across all RGB channels.
    public func texture(from multiArray: MLMultiArray, normalize: Bool = true) -> MTLTexture? {
        let shape = multiArray.shape.map { $0.intValue }
        let strides = multiArray.strides.map { $0.intValue }
        let width: Int
        let height: Int
        let rowDimension: Int
        let columnDimension: Int

        if shape.count == 3 {
            height = shape[1]
            width = shape[2]
            rowDimension = 1
            columnDimension = 2
        } else if shape.count == 2 {
            height = shape[0]
            width = shape[1]
            rowDimension = 0
            columnDimension = 1
        } else {
            return nil
        }
        guard strides.count == shape.count else { return nil }
        guard strides.allSatisfy({ $0 >= 0 }) else { return nil }
        guard width > 0, height > 0 else { return nil }

        let count = width * height
        var floatData = [Float](repeating: 0, count: count)

        func elementOffset(x: Int, y: Int) -> Int {
            y * strides[rowDimension] + x * strides[columnDimension]
        }
        // deprecated な dataPointer の代わりに withUnsafeBytes を使う
        // （型は dataType と一致させる必要があるため switch 側で分岐する。
        // withUnsafeBufferPointer(ofType:) は Float16/Int8 の scalar conformance が
        // macOS 15/26 以降のため、macOS 14 でも使える raw バイト API を採用）
        func copyElements<T>(_ type: T.Type, _ convert: (T) -> Float) {
            multiArray.withUnsafeBytes { raw in
                let buf = raw.bindMemory(to: T.self)
                for y in 0..<height {
                    for x in 0..<width {
                        floatData[y * width + x] = convert(buf[elementOffset(x: x, y: y)])
                    }
                }
            }
        }

        switch multiArray.dataType {
        case .float32:
            copyElements(Float.self) { $0 }
        case .double:
            copyElements(Double.self) { Float($0) }
        case .int32:
            copyElements(Int32.self) { Float($0) }
        case .float16:
            copyElements(Float16.self) { Float($0) }
        default:
            // MLMultiArrayDataType.int8 (rawValue 131080) は macOS 26.0+ SDK でのみ利用可能なため、
            // 古い SDK でのコンパイルエラーを避けるために rawValue で比較します。
            if multiArray.dataType.rawValue == 131080 {
                copyElements(Int8.self) { Float($0) }
            } else {
                metaphorWarning("Unsupported MLMultiArray dataType: \(multiArray.dataType.rawValue)")
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
