import Metal

/// metaphor ライブラリの中央エラー型
///
/// ## エラーハンドリング規約
/// - **初期化時の失敗**: ``MetaphorError`` をスロー
/// - **ランタイムの失敗** (描画中): `metaphorWarning()` でログ出力、スローしない
/// - **独立モジュール** (Audio, Network, Physics): 各自のエラー型を使用
public enum MetaphorError: Error, CustomStringConvertible, LocalizedError {

    // MARK: - Core (デバイス, キュー, バッファ, テクスチャ)

    /// Metal デバイスを取得できなかった
    case deviceNotAvailable

    /// 指定されたサイズとフォーマットでテクスチャを作成できなかった
    case textureCreationFailed(width: Int, height: Int, format: String)

    /// Metal コマンドキューを作成できなかった
    case commandQueueCreationFailed

    /// Metal バッファを確保できなかった
    case bufferCreationFailed(size: Int)

    /// スケッチコンテキストが利用できない (`setup()` または `draw()` の外で呼び出された)
    case contextUnavailable(method: String)

    // MARK: - シェーダー & パイプライン

    /// シェーダーのコンパイルに失敗した
    case shaderCompilationFailed(name: String, underlying: Error)

    /// レンダーパイプラインステートを作成できなかった
    case pipelineCreationFailed(name: String, underlying: Error)

    /// 指定されたシェーダー関数がシェーダーライブラリに見つからなかった
    case shaderNotFound(String)

    // MARK: - Canvas

    /// Canvas2D 操作の失敗
    case canvas(CanvasFailure)

    // MARK: - ジオメトリ & メッシュ

    /// メッシュ操作の失敗
    case mesh(MeshFailure)

    // MARK: - 画像

    /// 画像操作の失敗
    case image(ImageFailure)

    // MARK: - マテリアル

    /// マテリアル操作の失敗
    case material(MaterialFailure)

    // MARK: - パーティクル

    /// パーティクルシステム操作の失敗
    case particle(ParticleFailure)

    // MARK: - MPS (Metal Performance Shaders)

    /// Metal Performance Shaders 操作の失敗
    case mps(MPSFailure)

    // MARK: - RenderGraph

    /// レンダーグラフ操作の失敗
    case renderGraph(RenderGraphFailure)

    // MARK: - エクスポート

    /// エクスポート操作の失敗
    case export(ExportFailure)

    // MARK: - コンピュート

    /// コンピュートカーネル操作の失敗
    case compute(ComputeFailure)

    // MARK: - ネストされた失敗型

    public enum CanvasFailure: Sendable {
        /// Canvas 頂点用の Metal バッファを作成できなかった
        case bufferCreationFailed
    }

    public enum MeshFailure: Sendable {
        /// メッシュファイルが見つからなかった
        case fileNotFound
        /// メッシュデータのパースに失敗した
        case parseError(String)
    }

    public enum ImageFailure: Sendable {
        /// ソース画像が無効、または CGImage への変換に失敗した
        case invalidImage
    }

    public enum MaterialFailure: Sendable {
        /// 指定されたシェーダー関数が見つからなかった
        case shaderNotFound(String)
    }

    public enum ParticleFailure: Sendable {
        /// GPU バッファの確保に失敗した
        case bufferCreationFailed
        /// 必要なシェーダー関数が見つからなかった
        case shaderNotFound(String)
    }

    public enum MPSFailure: Sendable {
        /// デバイスが Metal Performance Shaders をサポートしていない
        case deviceNotSupported
        /// アクセラレーション構造体のビルドに失敗した
        case accelerationStructureBuildFailed(String)
        /// テクスチャ操作に失敗した
        case textureOperationFailed(String)
        /// レイ交差テストに失敗した
        case intersectionFailed(String)
        /// シーン構成が無効
        case invalidScene(String)
    }

    public enum RenderGraphFailure: Sendable {
        /// 必要なマージシェーダー関数が見つからなかった
        case shaderNotFound(String)
    }

    public enum ExportFailure: Sendable {
        /// キャプチャされたフレームがない
        case noFrames
        /// 画像デスティネーションを作成できなかった
        case destinationCreationFailed
        /// 出力ファイルのファイナライズに失敗した
        case finalizationFailed
        /// AVAssetWriter がエラーを検出した
        case writerFailed(String)
        /// endRecord() 呼び出し時に録画がアクティブでなかった
        case notRecording
    }

    public enum ComputeFailure: Sendable {
        /// 指定されたコンピュート関数が見つからなかった
        case functionNotFound(String)
    }

    // MARK: - Description

    public var description: String {
        switch self {
        case .deviceNotAvailable:
            "[metaphor] Metal device is not available"
        case .textureCreationFailed(let w, let h, let format):
            "[metaphor] Failed to create \(format) texture (\(w)x\(h))"
        case .commandQueueCreationFailed:
            "[metaphor] Failed to create command queue"
        case .bufferCreationFailed(let size):
            "[metaphor] Failed to create buffer (size: \(size))"
        case .contextUnavailable(let method):
            "[metaphor] Sketch context is not available in \(method). Ensure this is called inside setup() or draw()."
        case .shaderCompilationFailed(let name, let err):
            "[metaphor] Failed to compile shader '\(name)': \(err)"
        case .pipelineCreationFailed(let name, let err):
            "[metaphor] Failed to create pipeline '\(name)': \(err)"
        case .shaderNotFound(let name):
            "[metaphor] Shader function not found: '\(name)'"
        case .canvas(let f):
            switch f {
            case .bufferCreationFailed:
                "[metaphor] Failed to create canvas vertex buffer"
            }
        case .mesh(let f):
            switch f {
            case .fileNotFound:
                "[metaphor] Mesh file not found"
            case .parseError(let detail):
                "[metaphor] Mesh parse error: \(detail)"
            }
        case .image(let f):
            switch f {
            case .invalidImage:
                "[metaphor] Invalid image or CGImage conversion failed"
            }
        case .material(let f):
            switch f {
            case .shaderNotFound(let name):
                "[metaphor] Material shader not found: '\(name)'"
            }
        case .particle(let f):
            switch f {
            case .bufferCreationFailed:
                "[metaphor] Failed to create particle buffers"
            case .shaderNotFound(let name):
                "[metaphor] Particle shader not found: '\(name)'"
            }
        case .mps(let f):
            switch f {
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
        case .renderGraph(let f):
            switch f {
            case .shaderNotFound(let name):
                "[metaphor] Render graph shader not found: '\(name)'"
            }
        case .export(let f):
            switch f {
            case .noFrames:
                "[metaphor] No frames captured for export"
            case .destinationCreationFailed:
                "[metaphor] Failed to create export destination"
            case .finalizationFailed:
                "[metaphor] Failed to finalize export file"
            case .writerFailed(let detail):
                "[metaphor] Video export failed: \(detail)"
            case .notRecording:
                "[metaphor] Export ended but was not recording"
            }
        case .compute(let f):
            switch f {
            case .functionNotFound(let name):
                "[metaphor] Compute function '\(name)' not found"
            }
        }
    }

    public var errorDescription: String? { description }
}

/// メッセージ文字列のみを保持する簡易エラー。
/// 説明のみが必要な場合に NSError の軽量な代替として使用します。
struct SimpleError: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
