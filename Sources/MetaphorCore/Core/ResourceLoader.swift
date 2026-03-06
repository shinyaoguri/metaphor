import Metal
import MetalKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Load resources asynchronously to avoid blocking the main thread.
///
/// ``ResourceLoader`` wraps `MTKTextureLoader` async methods and provides
/// convenience APIs for loading images and models off the main thread.
@MainActor
public final class ResourceLoader {
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader

    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }

    private static var textureOptions: [MTKTextureLoader.Option: Any] {
        [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false,
        ]
    }

    // MARK: - Async Image Loading

    /// Load an image from a file path asynchronously.
    ///
    /// The file I/O and texture decoding happen off the main thread via
    /// `MTKTextureLoader`'s async API.
    ///
    /// - Parameter path: The absolute file path to the image.
    /// - Returns: A new ``MImage`` backed by the loaded texture.
    public func loadImageAsync(path: String) async throws -> MImage {
        let url = URL(fileURLWithPath: path)
        let texture = try await textureLoader.newTexture(
            URL: url, options: Self.textureOptions
        )
        return MImage(texture: texture)
    }

    /// Load a named image resource asynchronously.
    ///
    /// - Parameter name: The name of the image resource in the bundle.
    /// - Returns: A new ``MImage`` backed by the loaded texture.
    public func loadImageAsync(named name: String) async throws -> MImage {
        let texture = try await textureLoader.newTexture(
            name: name, scaleFactor: 1.0, bundle: nil, options: Self.textureOptions
        )
        return MImage(texture: texture)
    }

    #if os(macOS)
    /// Load an image from an `NSImage` asynchronously.
    ///
    /// - Parameter nsImage: The `NSImage` to convert.
    /// - Returns: A new ``MImage`` backed by the loaded texture.
    public func loadImageAsync(nsImage: NSImage) async throws -> MImage {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MetaphorError.image(.invalidImage)
        }
        let texture = try await textureLoader.newTexture(
            cgImage: cgImage, options: Self.textureOptions
        )
        return MImage(texture: texture)
    }
    #elseif os(iOS)
    /// Load an image from a `UIImage` asynchronously.
    ///
    /// - Parameter uiImage: The `UIImage` to convert.
    /// - Returns: A new ``MImage`` backed by the loaded texture.
    public func loadImageAsync(uiImage: UIImage) async throws -> MImage {
        guard let cgImage = uiImage.cgImage else {
            throw MetaphorError.image(.invalidImage)
        }
        let texture = try await textureLoader.newTexture(
            cgImage: cgImage, options: Self.textureOptions
        )
        return MImage(texture: texture)
    }
    #endif

    // MARK: - Async Model Loading

    /// Load a 3D model asynchronously.
    ///
    /// Model I/O requires MainActor, but wrapping in an async function lets
    /// callers use `await` and integrate with structured concurrency.
    ///
    /// - Parameters:
    ///   - path: The file path to the model.
    ///   - normalize: Whether to normalize the bounding box.
    /// - Returns: The loaded ``Mesh``.
    public func loadModelAsync(path: String, normalize: Bool = true) async throws -> Mesh {
        let url = URL(fileURLWithPath: path)
        return try ModelIOLoader.load(device: device, url: url, normalize: normalize)
    }
}
