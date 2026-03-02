import Metal

/// metaphor ライブラリの統一エラー型
public enum MetaphorError: Error, CustomStringConvertible {
    /// Metal デバイスの取得に失敗
    case deviceNotAvailable

    /// テクスチャの作成に失敗
    case textureCreationFailed(width: Int, height: Int, format: String)

    /// コマンドキューの作成に失敗
    case commandQueueCreationFailed

    /// シェーダーのコンパイルに失敗
    case shaderCompilationFailed(name: String, underlying: Error)

    /// レンダーパイプラインの作成に失敗
    case pipelineCreationFailed(name: String, underlying: Error)

    /// バッファの作成に失敗
    case bufferCreationFailed(size: Int)

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
        }
    }
}
