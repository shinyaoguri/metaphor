import CoreML
import Foundation

/// CoreML / Vision 統合のエラー型
public enum MLError: Error, LocalizedError {
    /// モデルファイルが見つからない
    case modelNotFound(String)

    /// モデルの読み込みに失敗
    case modelLoadFailed(String, underlying: Error)

    /// 推論に失敗
    case inferenceFailed(String)

    /// Vision リクエストに失敗
    case visionRequestFailed(String, underlying: Error)

    /// テクスチャの変換に失敗
    case textureConversionFailed(String)

    /// モデルの入出力形式が不正
    case invalidModelFormat(String)

    /// 非対応のフィーチャータイプ
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
