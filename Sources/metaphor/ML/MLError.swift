import CoreML
import Foundation

/// Represent errors from the CoreML and Vision integration subsystem.
public enum MLError: Error, LocalizedError {
    /// The model file was not found at the specified path.
    case modelNotFound(String)

    /// The model failed to load.
    case modelLoadFailed(String, underlying: Error)

    /// Inference failed.
    case inferenceFailed(String)

    /// A Vision request failed.
    case visionRequestFailed(String, underlying: Error)

    /// Texture conversion failed.
    case textureConversionFailed(String)

    /// The model has an invalid input/output format.
    case invalidModelFormat(String)

    /// The feature type is unsupported.
    case unsupportedFeatureType(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "[metaphor] ML model not found: \(path)"
        case .modelLoadFailed(let name, let err):
            return "[metaphor] Failed to load ML model '\(name)': \(err)"
        case .inferenceFailed(let detail):
            return "[metaphor] ML inference failed: \(detail)"
        case .visionRequestFailed(let name, let err):
            return "[metaphor] Vision request '\(name)' failed: \(err)"
        case .textureConversionFailed(let detail):
            return "[metaphor] Texture conversion failed: \(detail)"
        case .invalidModelFormat(let detail):
            return "[metaphor] Invalid model format: \(detail)"
        case .unsupportedFeatureType(let type):
            return "[metaphor] Unsupported feature type: \(type)"
        }
    }
}
