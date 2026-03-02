/// MPS サブシステムのエラー型
public enum MPSError: Error, LocalizedError, Sendable {
    /// デバイスが MPS をサポートしていない
    case deviceNotSupported
    /// アクセラレーション構造体の構築に失敗
    case accelerationStructureBuildFailed(String)
    /// テクスチャ操作に失敗
    case textureOperationFailed(String)
    /// レイトレーシング交差テストに失敗
    case intersectionFailed(String)
    /// 無効なシーン構成
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
