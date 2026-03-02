import Metal

/// Unified error type for the metaphor library.
///
/// All errors thrown by metaphor's core systems are represented by cases of this enum,
/// providing consistent error handling across the library.
public enum MetaphorError: Error, CustomStringConvertible, LocalizedError {
    /// The Metal device could not be obtained.
    case deviceNotAvailable

    /// A texture could not be created with the specified dimensions and format.
    case textureCreationFailed(width: Int, height: Int, format: String)

    /// The Metal command queue could not be created.
    case commandQueueCreationFailed

    /// A shader failed to compile.
    case shaderCompilationFailed(name: String, underlying: Error)

    /// A render pipeline state could not be created.
    case pipelineCreationFailed(name: String, underlying: Error)

    /// A Metal buffer could not be allocated.
    case bufferCreationFailed(size: Int)

    /// The specified post-process shader was not found in the shader library.
    case postProcessShaderNotFound(String)

    public var description: String {
        switch self {
        case .deviceNotAvailable:
            return "[metaphor] Metal device is not available"
        case .textureCreationFailed(let w, let h, let format):
            return "[metaphor] Failed to create \(format) texture (\(w)x\(h))"
        case .commandQueueCreationFailed:
            return "[metaphor] Failed to create command queue"
        case .shaderCompilationFailed(let name, let err):
            return "[metaphor] Failed to compile shader '\(name)': \(err)"
        case .pipelineCreationFailed(let name, let err):
            return "[metaphor] Failed to create pipeline '\(name)': \(err)"
        case .bufferCreationFailed(let size):
            return "[metaphor] Failed to create buffer (size: \(size))"
        case .postProcessShaderNotFound(let name):
            return "[metaphor] Post-process shader not found: '\(name)'"
        }
    }

    public var errorDescription: String? { description }
}
