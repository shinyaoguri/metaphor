import Metal
import MetaphorCore

/// Shared factory for Metal test resources.
///
/// Provides cached device, shader library, and convenience factory methods
/// to eliminate boilerplate in GPU-dependent tests.
///
/// Usage:
/// ```swift
/// @Suite("MyFeature", .enabled(if: MetalTestHelper.isGPUAvailable))
/// @MainActor
/// struct MyTests {
///     @Test func example() throws {
///         let canvas = try MetalTestHelper.canvas2D()
///         // ...
///     }
/// }
/// ```
@MainActor
public struct MetalTestHelper: Sendable {

    /// The shared Metal device, or `nil` if no GPU is available.
    public nonisolated(unsafe) static let device: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// Whether a Metal-capable GPU is available on this machine.
    /// `nonisolated` so it can be used in `@Suite(.enabled(if:))` trait closures.
    public nonisolated static var isGPUAvailable: Bool { device != nil }

    // MARK: - Core Factories

    /// Create a ``ShaderLibrary`` using the shared device.
    public static func shaderLibrary() throws -> ShaderLibrary {
        guard let device else { throw TestHelperError.noDevice }
        return try ShaderLibrary(device: device)
    }

    /// Create a ``DepthStencilCache`` using the shared device.
    public static func depthStencilCache() -> DepthStencilCache {
        DepthStencilCache(device: device!)
    }

    /// Create a ``Canvas2D`` with sensible defaults.
    public static func canvas2D(
        width: Float = 1920,
        height: Float = 1080,
        sampleCount: Int = 1
    ) throws -> Canvas2D {
        guard let device else { throw TestHelperError.noDevice }
        let shaderLib = try shaderLibrary()
        let depthCache = depthStencilCache()
        return try Canvas2D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: width,
            height: height,
            sampleCount: sampleCount
        )
    }

    /// Create a ``Canvas3D`` with sensible defaults.
    public static func canvas3D(
        width: Float = 1920,
        height: Float = 1080,
        sampleCount: Int = 1
    ) throws -> Canvas3D {
        guard let device else { throw TestHelperError.noDevice }
        let shaderLib = try shaderLibrary()
        let depthCache = depthStencilCache()
        return try Canvas3D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: width,
            height: height,
            sampleCount: sampleCount
        )
    }

    /// Create a ``MetaphorRenderer`` with sensible defaults.
    public static func renderer(
        width: Int = 1920,
        height: Int = 1080
    ) throws -> MetaphorRenderer {
        try MetaphorRenderer(width: width, height: height)
    }

    // MARK: - Texture Helpers

    /// Create a simple 2D texture for testing.
    public static func makeTexture(
        width: Int = 64,
        height: Int = 64,
        format: MTLPixelFormat = .bgra8Unorm,
        usage: MTLTextureUsage = [.shaderRead],
        storageMode: MTLStorageMode = .shared
    ) -> MTLTexture? {
        guard let device else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = usage
        desc.storageMode = storageMode
        return device.makeTexture(descriptor: desc)
    }

    /// Create a command queue from the shared device.
    public static func commandQueue() -> MTLCommandQueue? {
        device?.makeCommandQueue()
    }
}

/// Errors specific to test helper setup.
public enum TestHelperError: Error, CustomStringConvertible {
    case noDevice

    public var description: String {
        switch self {
        case .noDevice: "No Metal device available"
        }
    }
}
