import MetaphorCore
import MetaphorMPS

// MARK: - MPS ブリッジ

extension Sketch {
    /// Creates an MPS (Metal Performance Shaders) image filter.
    ///
    /// - Returns: A new ``MetaphorMPS/MPSImageFilterWrapper`` instance.
    public func createMPSFilter() -> MPSImageFilterWrapper {
        MPSImageFilterWrapper(
            device: context.renderer.device, commandQueue: context.renderer.commandQueue)
    }

    /// Creates a ray tracer for GPU-accelerated ray intersection queries.
    ///
    /// Uses the native Metal Ray Tracing API for inline intersection tests.
    /// - Parameters:
    ///   - width: The output image width, in pixels.
    ///   - height: The output image height, in pixels.
    /// - Returns: A new ``MetaphorMPS/MPSRayTracer`` instance.
    /// - Throws: ``MetaphorCore/MetaphorError``. A missing bundled shader source or
    ///   kernel function gives ``MetaphorCore/MetaphorError/mps(_:)`` with
    ///   ``MetaphorCore/MetaphorError/MPSFailure/accelerationStructureBuildFailed(_:)``、
    ///   a failed MSL compilation gives
    ///   ``MetaphorCore/MetaphorError/shaderCompilationFailed(name:underlying:)``、
    ///   and a compute pipeline that cannot be created gives
    ///   ``MetaphorCore/MetaphorError/pipelineCreationFailed(name:underlying:)``。
    public func createRayTracer(width: Int, height: Int) throws -> MPSRayTracer {
        try MPSRayTracer(
            device: context.renderer.device, commandQueue: context.renderer.commandQueue,
            width: width, height: height)
    }
}
