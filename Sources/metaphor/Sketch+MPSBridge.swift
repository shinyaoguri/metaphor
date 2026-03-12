import MetaphorCore
import MetaphorMPS

// MARK: - MPS Bridge

extension Sketch {
    /// Create an MPS (Metal Performance Shaders) image filter.
    ///
    /// - Returns: A new ``MetaphorMPS/MPSImageFilterWrapper`` instance.
    public func createMPSFilter() -> MPSImageFilterWrapper {
        MPSImageFilterWrapper(device: context.renderer.device, commandQueue: context.renderer.commandQueue)
    }

    /// Create an MPS ray tracer for GPU-accelerated ray intersection queries.
    ///
    /// - Parameters:
    ///   - width: The output image width in pixels.
    ///   - height: The output image height in pixels.
    /// - Returns: A new ``MetaphorMPS/MPSRayTracer`` instance.
    @available(macOS, deprecated: 14.0, message: "Uses deprecated MPS ray tracing APIs; migrate to Metal ray tracing APIs")
    public func createRayTracer(width: Int, height: Int) throws -> MPSRayTracer {
        try MPSRayTracer(device: context.renderer.device, commandQueue: context.renderer.commandQueue, width: width, height: height)
    }
}
