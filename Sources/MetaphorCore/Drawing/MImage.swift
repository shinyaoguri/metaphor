import Metal
import MetalKit
import AppKit

/// Represent an image by wrapping an `MTLTexture`.
@MainActor
public final class MImage {
    /// The underlying Metal texture backing this image.
    public private(set) var texture: MTLTexture

    /// The width of the image in pixels.
    public private(set) var width: Float

    /// The height of the image in pixels.
    public private(set) var height: Float

    /// Create an image by loading a texture from a file path.
    ///
    /// - Parameters:
    ///   - path: The absolute file path to the image.
    ///   - device: The Metal device used to create the texture.
    /// - Throws: An error if the texture cannot be loaded from the given path.
    public init(path: String, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        let url = URL(fileURLWithPath: path)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false
        ]
        self.texture = try loader.newTexture(URL: url, options: options)
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    /// Create an image by loading a named resource from the app bundle.
    ///
    /// - Parameters:
    ///   - name: The name of the image resource in the bundle.
    ///   - device: The Metal device used to create the texture.
    /// - Throws: An error if the named resource cannot be found or loaded.
    public init(named name: String, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false
        ]
        self.texture = try loader.newTexture(name: name, scaleFactor: 1.0, bundle: nil, options: options)
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    /// Create an image from an `NSImage`.
    ///
    /// - Parameters:
    ///   - nsImage: The `NSImage` to convert into a Metal texture.
    ///   - device: The Metal device used to create the texture.
    /// - Throws: ``MetaphorError/image(_:)`` if the `NSImage` cannot be converted to a `CGImage`.
    public init(nsImage: NSImage, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MetaphorError.image(.invalidImage)
        }
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false
        ]
        self.texture = try loader.newTexture(cgImage: cgImage, options: options)
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    /// Create an image from an existing `MTLTexture`.
    ///
    /// - Parameter texture: The Metal texture to wrap.
    public init(texture: MTLTexture) {
        self.texture = texture
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    // MARK: - Pixel Access

    /// The raw RGBA pixel data, populated after calling ``loadPixels()``.
    public var pixels: [UInt8] = []

    /// Whether the GPU texture may have changed since the last ``loadPixels()`` call.
    /// When true, the next ``loadPixels()`` reads from the GPU; otherwise it
    /// reuses the existing CPU array (avoiding allocation, readback, and conversion).
    private var needsGPUReadback: Bool = true

    /// Load pixel data from the GPU texture into the ``pixels`` array on the CPU.
    ///
    /// For textures with private storage mode, this method creates a staging
    /// texture with managed storage and performs a blit copy before reading.
    /// The resulting data is converted from BGRA to RGBA order.
    ///
    /// If the CPU array is already populated and the GPU texture has not changed
    /// (no ``replaceTexture(_:)`` or GPU filter since the last call), this method
    /// returns immediately — avoiding allocation, readback, and conversion overhead.
    public func loadPixels() {
        let w = Int(width)
        let h = Int(height)
        let bytesPerRow = w * 4
        let count = bytesPerRow * h

        // Reuse existing CPU data when the texture hasn't changed.
        if !needsGPUReadback && pixels.count == count {
            return
        }

        if pixels.count != count {
            pixels = [UInt8](repeating: 0, count: count)
        }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: w, height: h, depth: 1))

        if texture.storageMode == .private {
            // Private texture: blit to a shared staging texture, then read back
            let device = texture.device
            guard let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                pixels = [UInt8](repeating: 0, count: count)
                return
            }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: texture.pixelFormat, width: w, height: h, mipmapped: false)
            desc.storageMode = .shared
            desc.usage = .shaderRead
            guard let staging = device.makeTexture(descriptor: desc),
                  let blit = commandBuffer.makeBlitCommandEncoder() else {
                pixels = [UInt8](repeating: 0, count: count)
                return
            }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: w, height: h, depth: 1),
                      to: staging, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            staging.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        } else {
            texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        }

        // Convert BGRA to RGBA
        pixels.withUnsafeMutableBufferPointer { buf in
            let ptr = buf.baseAddress!
            for i in stride(from: 0, to: count, by: 4) {
                let tmp = ptr[i]
                ptr[i] = ptr[i + 2]
                ptr[i + 2] = tmp
            }
        }

        needsGPUReadback = false
    }

    /// Write the CPU ``pixels`` array back to the GPU texture.
    ///
    /// The pixel data is converted from RGBA back to BGRA before uploading.
    /// If the current texture has private storage mode, a new managed texture
    /// is created to replace it, since private textures cannot be written from the CPU.
    public func updatePixels() {
        let w = Int(width)
        let h = Int(height)
        let bytesPerRow = w * 4
        let count = bytesPerRow * h
        guard pixels.count == count else { return }

        // Convert RGBA to BGRA in-place using unsafe pointer for bounds-check-free access
        pixels.withUnsafeMutableBufferPointer { buf in
            let ptr = buf.baseAddress!
            for i in stride(from: 0, to: count, by: 4) {
                let tmp = ptr[i]
                ptr[i] = ptr[i + 2]
                ptr[i + 2] = tmp
            }
        }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: w, height: h, depth: 1))

        if texture.storageMode == .private {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: texture.pixelFormat, width: w, height: h, mipmapped: false)
            desc.storageMode = .shared
            desc.usage = [.shaderRead]
            guard let newTexture = texture.device.makeTexture(descriptor: desc) else {
                // Swap back on failure
                pixels.withUnsafeMutableBufferPointer { buf in
                    let ptr = buf.baseAddress!
                    for i in stride(from: 0, to: count, by: 4) {
                        let tmp = ptr[i]
                        ptr[i] = ptr[i + 2]
                        ptr[i + 2] = tmp
                    }
                }
                return
            }
            newTexture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
            self.texture = newTexture
        } else {
            texture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
        }

        // Convert back to RGBA so pixels array stays in user-facing format
        pixels.withUnsafeMutableBufferPointer { buf in
            let ptr = buf.baseAddress!
            for i in stride(from: 0, to: count, by: 4) {
                let tmp = ptr[i]
                ptr[i] = ptr[i + 2]
                ptr[i + 2] = tmp
            }
        }
    }

    /// Return the color of the pixel at the specified coordinates.
    ///
    /// Call ``loadPixels()`` before using this method to ensure the ``pixels``
    /// array is populated.
    ///
    /// - Parameters:
    ///   - x: The horizontal pixel coordinate.
    ///   - y: The vertical pixel coordinate.
    /// - Returns: The ``Color`` at the given position, or black if out of bounds or pixels are not loaded.
    public func get(_ x: Int, _ y: Int) -> Color {
        let w = Int(width)
        guard x >= 0, x < w, y >= 0, y < Int(height) else { return .black }
        guard !pixels.isEmpty else { return .black }
        let i = (y * w + x) * 4
        return Color(
            r: Float(pixels[i]) / 255.0,
            g: Float(pixels[i + 1]) / 255.0,
            b: Float(pixels[i + 2]) / 255.0,
            a: Float(pixels[i + 3]) / 255.0
        )
    }

    /// Set the color of the pixel at the specified coordinates.
    ///
    /// Changes are stored in the ``pixels`` array and are not reflected on
    /// the GPU until ``updatePixels()`` is called.
    ///
    /// - Parameters:
    ///   - x: The horizontal pixel coordinate.
    ///   - y: The vertical pixel coordinate.
    ///   - color: The ``Color`` to write at the given position.
    public func set(_ x: Int, _ y: Int, _ color: Color) {
        let w = Int(width)
        guard x >= 0, x < w, y >= 0, y < Int(height) else { return }
        let bytesPerRow = w * 4
        if pixels.isEmpty {
            pixels = [UInt8](repeating: 0, count: bytesPerRow * Int(height))
        }
        let i = (y * w + x) * 4
        pixels[i] = UInt8(max(0, min(255, color.r * 255)))
        pixels[i + 1] = UInt8(max(0, min(255, color.g * 255)))
        pixels[i + 2] = UInt8(max(0, min(255, color.b * 255)))
        pixels[i + 3] = UInt8(max(0, min(255, color.a * 255)))
    }

    /// Replace the backing texture with a new one, typically after applying a GPU filter.
    ///
    /// This resets the ``pixels`` array since the CPU data is no longer in sync.
    ///
    /// - Parameter newTexture: The new Metal texture to use.
    public func replaceTexture(_ newTexture: MTLTexture) {
        self.texture = newTexture
        self.width = Float(newTexture.width)
        self.height = Float(newTexture.height)
        self.pixels = []
        self.needsGPUReadback = true
    }

    /// Apply an image filter by performing ``loadPixels()``, processing, and ``updatePixels()`` in one step.
    ///
    /// - Parameter type: The ``FilterType`` specifying which filter to apply.
    public func filter(_ type: FilterType) {
        ImageFilter.apply(type, to: self)
    }

    /// Create an empty image suitable for pixel manipulation.
    ///
    /// The returned image has managed storage mode with both shader read and
    /// write usage, and its ``pixels`` array is pre-allocated with zeroes.
    ///
    /// - Parameters:
    ///   - width: The width of the image in pixels.
    ///   - height: The height of the image in pixels.
    ///   - device: The Metal device used to create the texture.
    /// - Returns: A new ``MImage`` instance, or `nil` if the texture could not be created.
    public static func createImage(_ width: Int, _ height: Int, device: MTLDevice) -> MImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        let img = MImage(texture: texture)
        img.pixels = [UInt8](repeating: 0, count: width * height * 4)
        return img
    }
}

