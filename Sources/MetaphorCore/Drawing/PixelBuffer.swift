import Metal

/// CPU からの直接ピクセル操作用の高性能ピクセルバッファ。
///
/// ピクセルデータを BGRA8Unorm フォーマット（Metal ネイティブ）のパックされた UInt32 として格納します。
/// Apple Silicon では、バッファバックドの共有テクスチャを使用して真のゼロコピー
/// アクセスを実現 — CPU 書き込みは統合メモリを介して即座に GPU から参照可能です。
///
/// UInt32 パッキング `(A << 24) | (R << 16) | (G << 8) | B` は
/// Metal の BGRA8Unorm レイアウトと Processing の ARGB int フォーマットの両方に一致します。
///
/// Usage:
/// ```swift
/// loadPixels()
/// pixels[y * Int(width) + x] = color(255, 0, 0)  // red pixel
/// updatePixels()
/// ```
@MainActor
public final class PixelBuffer {

    /// ピクセルバッファの幅（ピクセル単位）。
    public let width: Int

    /// ピクセルバッファの高さ（ピクセル単位）。
    public let height: Int

    /// 統合メモリでバックされた共有 Metal テクスチャ。
    public let texture: MTLTexture

    /// パックされた UInt32 値としてのピクセルデータへの直接アクセス。
    ///
    /// 各要素は BGRA パックされた色: `(A << 24) | (R << 16) | (G << 8) | B`。
    /// `pixels[y * width + x]` でインデックスします。
    public let pixels: UnsafeMutableBufferPointer<UInt32>

    /// ゼロコピーパス用のバッキング MTLBuffer（フォールバック使用時は nil）。
    private let backingBuffer: MTLBuffer?

    /// フォールバックパス用の生メモリ（ゼロコピーバッファバックドテクスチャ使用時は nil）。
    nonisolated(unsafe) private let rawMemory: UnsafeMutablePointer<UInt32>?
    private let bytesPerRow: Int

    /// 指定された寸法でピクセルバッファを作成します。
    ///
    /// 幅がデバイスのリニアテクスチャアライメントを満たす場合（Apple Silicon では width % 4 == 0）、
    /// 真のゼロコピーアクセス用にバッファバックドの共有テクスチャが作成されます。
    /// それ以外の場合は、共有テクスチャと `texture.replace()` アップロードによる
    /// 生メモリにフォールバックします。
    ///
    /// - Parameters:
    ///   - width: ピクセル単位の幅。
    ///   - height: ピクセル単位の高さ。
    ///   - device: Metal デバイス。
    init?(width: Int, height: Int, device: MTLDevice) {
        guard width > 0, height > 0 else { return nil }

        let count = width * height
        let rawBytesPerRow = width * 4
        let alignment = device.minimumLinearTextureAlignment(for: .bgra8Unorm)
        let isAligned = rawBytesPerRow % alignment == 0

        if isAligned {
            // ゼロコピーパス: バッファバックド共有テクスチャ。
            // CPU が統合メモリに直接書き込み、GPU が同じバイトを読み取る。
            let totalBytes = rawBytesPerRow * height
            guard let buffer = device.makeBuffer(length: totalBytes, options: .storageModeShared) else {
                return nil
            }
            memset(buffer.contents(), 0, totalBytes)

            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.storageMode = .shared
            desc.usage = [.shaderRead]

            guard let tex = buffer.makeTexture(
                descriptor: desc,
                offset: 0,
                bytesPerRow: rawBytesPerRow
            ) else {
                return nil
            }

            self.width = width
            self.height = height
            self.texture = tex
            self.backingBuffer = buffer
            self.rawMemory = nil
            self.bytesPerRow = rawBytesPerRow
            self.pixels = UnsafeMutableBufferPointer(
                start: buffer.contents().bindMemory(to: UInt32.self, capacity: count),
                count: count
            )
        } else {
            // フォールバックパス: 生メモリ + 共有テクスチャ + texture.replace()。
            // 幅がバッファバックドテクスチャのアライメントを満たさない場合に使用。
            let mem = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
            mem.initialize(repeating: 0, count: count)

            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.storageMode = .shared
            desc.usage = [.shaderRead]

            guard let tex = device.makeTexture(descriptor: desc) else {
                mem.deallocate()
                return nil
            }

            self.width = width
            self.height = height
            self.texture = tex
            self.backingBuffer = nil
            self.rawMemory = mem
            self.bytesPerRow = rawBytesPerRow
            self.pixels = UnsafeMutableBufferPointer(start: mem, count: count)
        }
    }

    /// ピクセルデータを GPU テクスチャにアップロードします。
    ///
    /// バッファバックドのゼロコピーパスを使用している場合、CPU 書き込みは
    /// 統合メモリを介して即座に GPU から参照可能なため、何もしません。
    /// フォールバックパスでのみ処理を実行します。
    func upload() {
        guard rawMemory != nil else { return }
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: rawMemory!,
            bytesPerRow: bytesPerRow
        )
    }

    deinit {
        rawMemory?.deallocate()
    }
}

// MARK: - Color Packing

/// グレースケール値を BGRA UInt32 にパックします。
///
/// - Parameter gray: 輝度値（0–255）。
/// - Returns: R=G=B=gray、A=255 のパックされた BGRA ピクセル。
@inlinable
public func color(_ gray: Float) -> UInt32 {
    let v = UInt32(max(0, min(255, gray)))
    return 0xFF00_0000 | (v << 16) | (v << 8) | v
}

/// RGB 値を BGRA UInt32 にパックします。
///
/// - Parameters:
///   - r: 赤成分（0–255）。
///   - g: 緑成分（0–255）。
///   - b: 青成分（0–255）。
/// - Returns: A=255 のパックされた BGRA ピクセル。
@inlinable
public func color(_ r: Float, _ g: Float, _ b: Float) -> UInt32 {
    let ri = UInt32(max(0, min(255, r)))
    let gi = UInt32(max(0, min(255, g)))
    let bi = UInt32(max(0, min(255, b)))
    return 0xFF00_0000 | (ri << 16) | (gi << 8) | bi
}

/// RGBA 値を BGRA UInt32 にパックします。
///
/// - Parameters:
///   - r: 赤成分（0–255）。
///   - g: 緑成分（0–255）。
///   - b: 青成分（0–255）。
///   - a: アルファ成分（0–255）。
/// - Returns: パックされた BGRA ピクセル。
@inlinable
public func color(_ r: Float, _ g: Float, _ b: Float, _ a: Float) -> UInt32 {
    let ri = UInt32(max(0, min(255, r)))
    let gi = UInt32(max(0, min(255, g)))
    let bi = UInt32(max(0, min(255, b)))
    let ai = UInt32(max(0, min(255, a)))
    return (ai << 24) | (ri << 16) | (gi << 8) | bi
}
