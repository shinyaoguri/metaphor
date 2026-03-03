/// Represent errors from the MPS subsystem.
public enum MPSError: Error, LocalizedError, Sendable {
    /// The device does not support Metal Performance Shaders.
    case deviceNotSupported
    /// The acceleration structure failed to build.
    case accelerationStructureBuildFailed(String)
    /// A texture operation failed.
    case textureOperationFailed(String)
    /// A ray intersection test failed.
    case intersectionFailed(String)
    /// The scene configuration is invalid.
    case invalidScene(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotSupported:
            "[metaphor] Device does not support Metal Performance Shaders"
        case .accelerationStructureBuildFailed(let detail):
            "[metaphor] MPS acceleration structure build failed: \(detail)"
        case .textureOperationFailed(let detail):
            "[metaphor] MPS texture operation failed: \(detail)"
        case .intersectionFailed(let detail):
            "[metaphor] MPS ray intersection failed: \(detail)"
        case .invalidScene(let detail):
            "[metaphor] Invalid MPS ray tracing scene: \(detail)"
        }
    }
}
