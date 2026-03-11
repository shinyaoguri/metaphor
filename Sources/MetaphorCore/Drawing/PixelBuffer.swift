import Metal

/// A high-performance pixel buffer for direct CPU pixel manipulation.
///
/// Stores pixel data as packed UInt32 in BGRA8Unorm format (Metal native).
/// On Apple Silicon, uses a buffer-backed shared texture for true zero-copy
/// access — CPU writes are immediately visible to the GPU via unified memory.
///
/// The UInt32 packing `(A << 24) | (R << 16) | (G << 8) | B` matches
/// both Metal's BGRA8Unorm layout and Processing's ARGB int format.
///
/// Usage:
/// ```swift
/// loadPixels()
/// pixels[y * Int(width) + x] = color(255, 0, 0)  // red pixel
/// updatePixels()
/// ```
@MainActor
public final class PixelBuffer {

    /// The width of the pixel buffer in pixels.
    public let width: Int

    /// The height of the pixel buffer in pixels.
    public let height: Int

    /// The shared Metal texture backed by unified memory.
    public let texture: MTLTexture

    /// Direct access to pixel data as packed UInt32 values.
    ///
    /// Each element is a BGRA-packed color: `(A << 24) | (R << 16) | (G << 8) | B`.
    /// Index with `pixels[y * width + x]`.
    public let pixels: UnsafeMutableBufferPointer<UInt32>

    /// The backing MTLBuffer for the zero-copy path (nil when using fallback).
    private let backingBuffer: MTLBuffer?

    /// Raw memory for the fallback path (nil when using zero-copy buffer-backed texture).
    nonisolated(unsafe) private let rawMemory: UnsafeMutablePointer<UInt32>?
    private let bytesPerRow: Int

    /// Create a pixel buffer for the given dimensions.
    ///
    /// When the width satisfies the device's linear texture alignment (width % 4 == 0
    /// on Apple Silicon), a buffer-backed shared texture is created for true zero-copy
    /// access. Otherwise, falls back to raw memory with a shared texture and
    /// `texture.replace()` upload.
    ///
    /// - Parameters:
    ///   - width: The width in pixels.
    ///   - height: The height in pixels.
    ///   - device: The Metal device.
    init?(width: Int, height: Int, device: MTLDevice) {
        guard width > 0, height > 0 else { return nil }

        let count = width * height
        let rawBytesPerRow = width * 4
        let alignment = device.minimumLinearTextureAlignment(for: .bgra8Unorm)
        let isAligned = rawBytesPerRow % alignment == 0

        if isAligned {
            // Zero-copy path: buffer-backed shared texture.
            // CPU writes directly to unified memory; GPU reads the same bytes.
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
            // Fallback path: raw memory + shared texture + texture.replace().
            // Used when width doesn't satisfy buffer-backed texture alignment.
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

    /// Upload the pixel data to the GPU texture.
    ///
    /// When using the buffer-backed zero-copy path, this is a no-op since
    /// CPU writes are immediately visible to the GPU via unified memory.
    /// Only performs work in the fallback path.
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

/// Pack a grayscale value into a BGRA UInt32.
///
/// - Parameter gray: Brightness value (0–255).
/// - Returns: A packed BGRA pixel with R=G=B=gray and A=255.
@inlinable
public func color(_ gray: Float) -> UInt32 {
    let v = UInt32(max(0, min(255, gray)))
    return 0xFF00_0000 | (v << 16) | (v << 8) | v
}

/// Pack RGB values into a BGRA UInt32.
///
/// - Parameters:
///   - r: Red component (0–255).
///   - g: Green component (0–255).
///   - b: Blue component (0–255).
/// - Returns: A packed BGRA pixel with A=255.
@inlinable
public func color(_ r: Float, _ g: Float, _ b: Float) -> UInt32 {
    let ri = UInt32(max(0, min(255, r)))
    let gi = UInt32(max(0, min(255, g)))
    let bi = UInt32(max(0, min(255, b)))
    return 0xFF00_0000 | (ri << 16) | (gi << 8) | bi
}

/// Pack RGBA values into a BGRA UInt32.
///
/// - Parameters:
///   - r: Red component (0–255).
///   - g: Green component (0–255).
///   - b: Blue component (0–255).
///   - a: Alpha component (0–255).
/// - Returns: A packed BGRA pixel.
@inlinable
public func color(_ r: Float, _ g: Float, _ b: Float, _ a: Float) -> UInt32 {
    let ri = UInt32(max(0, min(255, r)))
    let gi = UInt32(max(0, min(255, g)))
    let bi = UInt32(max(0, min(255, b)))
    let ai = UInt32(max(0, min(255, a)))
    return (ai << 24) | (ri << 16) | (gi << 8) | bi
}
