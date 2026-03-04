@preconcurrency import Metal

/// Hold Metal resources that can be shared across multiple windows and renderers.
///
/// When using multi-window rendering, each ``MetaphorRenderer`` can share the
/// same device, command queue, shader library, and depth-stencil cache to avoid
/// duplicating expensive GPU-side objects.
@MainActor
public final class SharedMetalResources {
    /// The Metal device used for all GPU resource creation.
    public let device: MTLDevice

    /// The command queue used to submit work to the GPU.
    public let commandQueue: MTLCommandQueue

    /// The shader library containing compiled Metal shader functions.
    public let shaderLibrary: ShaderLibrary

    /// The depth-stencil state cache shared across renderers.
    public let depthStencilCache: DepthStencilCache

    /// Create shared Metal resources.
    ///
    /// - Parameter device: The Metal device to use, or `nil` to use the system default.
    /// - Throws: ``MetaphorError`` if the device or command queue cannot be created.
    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else {
            throw MetaphorError.deviceNotAvailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetaphorError.commandQueueCreationFailed
        }
        self.device = device
        self.commandQueue = commandQueue
        self.shaderLibrary = try ShaderLibrary(device: device)
        self.depthStencilCache = DepthStencilCache(device: device)
    }
}
