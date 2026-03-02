@preconcurrency import Metal

/// Wrap a GPU compute kernel with its pipeline state and metadata.
///
/// Compile a compute pipeline state from an MSL source string and expose
/// thread-group size metadata for dispatch configuration.
///
/// ```swift
/// let kernel = try createComputeKernel(
///     source: "kernel void update(...) { ... }",
///     function: "update"
/// )
/// ```
@MainActor
public final class ComputeKernel {
    /// The compiled compute pipeline state.
    public let pipelineState: MTLComputePipelineState

    /// Return the maximum number of threads per threadgroup.
    public var maxTotalThreadsPerThreadgroup: Int {
        pipelineState.maxTotalThreadsPerThreadgroup
    }

    /// Return the recommended 1D threadgroup size (SIMD width).
    public var threadExecutionWidth: Int {
        pipelineState.threadExecutionWidth
    }

    /// Create a compute kernel by compiling MSL source code at runtime.
    /// - Parameters:
    ///   - device: The Metal device used for compilation.
    ///   - source: The MSL source code string.
    ///   - functionName: The name of the kernel function to look up.
    /// - Throws: `ComputeKernelError.functionNotFound` if the function name is not found,
    ///   or a Metal compilation error.
    public init(device: MTLDevice, source: String, functionName: String) throws {
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: functionName) else {
            throw ComputeKernelError.functionNotFound(functionName)
        }
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }

    /// Create a compute kernel from a pre-compiled Metal function.
    /// - Parameters:
    ///   - device: The Metal device used to create the pipeline state.
    ///   - function: A pre-compiled `MTLFunction`.
    /// - Throws: A Metal pipeline creation error.
    public init(device: MTLDevice, function: MTLFunction) throws {
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}

/// Represent errors that can occur when creating a compute kernel.
public enum ComputeKernelError: Error, CustomStringConvertible {
    case functionNotFound(String)

    public var description: String {
        switch self {
        case .functionNotFound(let name):
            return "Compute function '\(name)' not found in shader source"
        }
    }
}
