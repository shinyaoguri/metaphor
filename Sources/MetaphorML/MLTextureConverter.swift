import CoreML
import CoreVideo
import Metal
import ObjectiveC.runtime

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
    ///
    /// - Important: `.private` ストレージのテクスチャでは GPU コピーの完了を
    ///   **同期的に待ちます**（`waitUntilCompleted`）。`draw()` 内で毎フレーム
    ///   呼ぶとフレーム落ちの原因になります。
    /// - Parameter texture: 入力テクスチャ（bgra8Unorm のみ対応）。
    /// - Returns: kCVPixelFormatType_32BGRA 形式の CVPixelBuffer。失敗時は nil。
    public func pixelBuffer(from texture: MTLTexture) -> CVPixelBuffer? {
        // BGRA8 前提のバイトコピーのため、他フォーマットは silent な
        // チャンネル化けになる前に弾く
        guard texture.pixelFormat == .bgra8Unorm else {
            print("[metaphor] MLTextureConverter.pixelBuffer(from:) requires bgra8Unorm, got \(texture.pixelFormat.rawValue)")
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
        guard status == kCVReturnSuccess,
              let cvTex = cvTexture,
              let mtlTexture = CVMetalTextureGetTexture(cvTex) else { return nil }

        // CoreVideo の契約上、`CVMetalTextureGetTexture` が返す MTLTexture は
        // ラッパー（cvTex）が生存している間のみ有効。返り値の MTLTexture に
        // ラッパーを関連付け、テクスチャと同じ寿命でラッパーを生かし続ける。
        // これがないと cvTex がスコープ終端で解放され、バッファ再利用による
        // 別フレーム参照や画像破損が起こり得る。
        objc_setAssociatedObject(
            mtlTexture, Self.cvTextureAssociationKey, cvTex, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return mtlTexture
    }

    /// ``texture(from:)`` がゼロコピーテクスチャに CVMetalTexture ラッパーを
    /// 関連付ける際に使用する安定した一意キー。
    private static let cvTextureAssociationKey = UnsafeRawPointer(
        UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    )

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
    ///
    /// - Important: `.private` ストレージのテクスチャでは GPU コピーの完了を
    ///   **同期的に待ちます**（`waitUntilCompleted`）。`draw()` 内で毎フレーム
    ///   呼ぶとフレーム落ちの原因になります。
    /// - Parameter texture: 入力 Metal テクスチャ（bgra8Unorm のみ対応）。
    /// - Returns: CGImage。失敗時は nil。
    public func cgImage(from texture: MTLTexture) -> CGImage? {
        // BGRA8 前提のバイトコピーのため、他フォーマットは silent な
        // チャンネル化けになる前に弾く
        guard texture.pixelFormat == .bgra8Unorm else {
            print("[metaphor] MLTextureConverter.cgImage(from:) requires bgra8Unorm, got \(texture.pixelFormat.rawValue)")
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

    /// 2D MLMultiArray（グレースケール）を MTLTexture に変換します。
    /// - Parameters:
    ///   - multiArray: 入力配列（形状: [1, height, width] または [height, width]）。
    ///   - normalize: true の場合、データに最小-最大正規化を適用します。
    /// - Returns: グレースケール値を全 RGB チャンネルに複製した bgra8Unorm テクスチャ。
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
