import Metal
import MetalKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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

    #if os(macOS)
    /// Create an image from an `NSImage`.
    ///
    /// - Parameters:
    ///   - nsImage: The `NSImage` to convert into a Metal texture.
    ///   - device: The Metal device used to create the texture.
    /// - Throws: ``MImageError/invalidImage`` if the `NSImage` cannot be converted to a `CGImage`.
    public init(nsImage: NSImage, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MImageError.invalidImage
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
    #elseif os(iOS)
    /// Create an image from a `UIImage`.
    ///
    /// - Parameters:
    ///   - uiImage: The `UIImage` to convert into a Metal texture.
    ///   - device: The Metal device used to create the texture.
    /// - Throws: ``MImageError/invalidImage`` if the `UIImage` does not contain a valid `CGImage`.
    public init(uiImage: UIImage, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        guard let cgImage = uiImage.cgImage else {
            throw MImageError.invalidImage
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
    #endif

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

    /// Load pixel data from the GPU texture into the ``pixels`` array on the CPU.
    ///
    /// For textures with private storage mode, this method creates a staging
    /// texture with managed storage and performs a blit copy before reading.
    /// The resulting data is converted from BGRA to RGBA order.
    public func loadPixels() {
        let w = Int(width)
        let h = Int(height)
        let bytesPerRow = w * 4
        pixels = [UInt8](repeating: 0, count: bytesPerRow * h)

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: w, height: h, depth: 1))

        if texture.storageMode == .private {
            // Private texture: blit to a managed staging texture, then read back
            let device = texture.device
            guard let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                pixels = []
                return
            }
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: texture.pixelFormat, width: w, height: h, mipmapped: false)
            desc.storageMode = .managed
            desc.usage = .shaderRead
            guard let staging = device.makeTexture(descriptor: desc),
                  let blit = commandBuffer.makeBlitCommandEncoder() else {
                pixels = []
                return
            }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: w, height: h, depth: 1),
                      to: staging, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.synchronize(resource: staging)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            staging.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        } else {
            texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        }

        // Convert BGRA to RGBA
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = pixels[i]
            pixels[i] = pixels[i + 2]
            pixels[i + 2] = b
        }
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
        guard pixels.count == bytesPerRow * h else { return }

        // Convert RGBA to BGRA
        var bgra = pixels
        for i in stride(from: 0, to: bgra.count, by: 4) {
            let r = bgra[i]
            bgra[i] = bgra[i + 2]
            bgra[i + 2] = r
        }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: w, height: h, depth: 1))

        if texture.storageMode == .private {
            // Cannot write to a private texture from the CPU; create a new managed texture as replacement
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: texture.pixelFormat, width: w, height: h, mipmapped: false)
            desc.storageMode = .managed
            desc.usage = [.shaderRead]
            guard let newTexture = texture.device.makeTexture(descriptor: desc) else { return }
            newTexture.replace(region: region, mipmapLevel: 0, withBytes: bgra, bytesPerRow: bytesPerRow)
            self.texture = newTexture
        } else {
            texture.replace(region: region, mipmapLevel: 0, withBytes: bgra, bytesPerRow: bytesPerRow)
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
    internal func replaceTexture(_ newTexture: MTLTexture) {
        self.texture = newTexture
        self.width = Float(newTexture.width)
        self.height = Float(newTexture.height)
        self.pixels = []
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
        desc.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        let img = MImage(texture: texture)
        img.pixels = [UInt8](repeating: 0, count: width * height * 4)
        return img
    }
}

/// Represent errors that can occur when creating an ``MImage``.
public enum MImageError: Error {
    /// The source image is invalid or could not be converted to a `CGImage`.
    case invalidImage
}
