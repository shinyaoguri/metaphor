import Metal

/// metaphor ライブラリの中央エラー型
///
/// ## エラーハンドリング規約
/// - **初期化時の失敗**: ``MetaphorError`` をスロー
/// - **ランタイムの失敗** (描画中): `metaphorWarning()` でログ出力、スローしない
/// - **独立モジュール** (Audio, Network, Physics): 各自のエラー型を使用
///
/// ## エラー契約 (ADR-0005 Decision 2 / Amendment 3)
///
/// `throws` と宣言された public API は、**そのモジュールのエラー型だけ**を投げます。
/// Metal・Foundation・MetalKit・AVFoundation など下層フレームワークの `NSError` を
/// そのまま素通りさせてはいけません。必ずこの型 (`MetaphorCore` と、それに依存する
/// `MetaphorMPS` / `MetaphorRenderGraph`) か、各独立モジュールのエラー型へ包みます。
/// 下層の原因はケースの `underlying` / `detail` に文字列として保存します。
///
/// この規約により `catch` 側は次のように書けます。
///
/// ```swift
/// do {
///     let image = try loadImage("missing.png")
/// } catch let error as MetaphorError {
///     // metaphor 由来の失敗はすべてここに来る
///     print(error.description)
/// }
/// ```
///
/// - Note: 将来 Swift の最小サポートが 6.0 以上になった時点で、この規約は
///   typed throws (`throws(MetaphorError)`) としてコンパイラに強制させる予定です
///   (SE-0413 は Swift 6.0 の機能で、最小サポートの Swift 5.10 ではパースできません)。
///   それまでは「投げるエラー型を統一し doc に明記する」ことで同じ予見可能性を担保します。
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

    /// API に渡されたパラメータが不正 (範囲外・前提条件違反など)
    case invalidParameter(String)

    // MARK: - シェーダー & パイプライン

    /// シェーダーのコンパイルに失敗した
    case shaderCompilationFailed(name: String, underlying: Error)

    /// レンダーパイプラインステートを作成できなかった
    case pipelineCreationFailed(name: String, underlying: Error)

    /// 指定されたシェーダー関数がシェーダーライブラリに見つからなかった
    case shaderNotFound(String)

    /// シェーダーソースファイルを読み込めなかった (コンパイル前段の I/O 失敗)
    case shaderSourceLoadFailed(path: String, detail: String)

    // MARK: - Canvas

    /// Canvas2D 操作の失敗
    case canvas(CanvasFailure)

    // MARK: - ジオメトリ & メッシュ

    /// メッシュ操作の失敗
    case mesh(MeshFailure)

    // MARK: - 画像

    /// 画像操作の失敗
    case image(ImageFailure)

    // MARK: - フォント

    /// フォント操作の失敗
    case font(FontFailure)

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

    // MARK: - データ IO

    /// データ IO（JSON/Table/Strings）操作の失敗
    case data(DataFailure)

    // MARK: - ネストされた失敗型

    public enum CanvasFailure: Sendable {
        /// Canvas 頂点用の Metal バッファを作成できなかった
        case bufferCreationFailed
    }

    public enum MeshFailure: Sendable {
        /// メッシュファイルが見つからなかった
        case fileNotFound
        /// メッシュファイルを読み込めなかった (不在・権限・I/O エラー)
        case loadFailed(path: String, detail: String)
        /// メッシュデータのパースに失敗した
        case parseError(String)
    }

    public enum ImageFailure: Sendable {
        /// ソース画像が無効、または CGImage への変換に失敗した
        case invalidImage
        /// 画像をテクスチャとして読み込めなかった (不在・非対応フォーマット・I/O エラー)
        ///
        /// `source` はファイルパス・アセット名など読み込み元の識別子です。
        case loadFailed(source: String, detail: String)
    }

    public enum FontFailure: Sendable {
        /// フォントファイルが見つからなかった
        case fileNotFound(path: String)
        /// フォントファイルにフォントが 1 つも入っていなかった (非対応フォーマット・破損)
        case noFontsInFile(path: String)
        /// フォントをプロセスへ登録できなかった
        case registrationFailed(path: String, detail: String)
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
        /// 出力ファイルの作成・移動・削除に失敗した
        case fileWriteFailed(path: String, detail: String)
    }

    public enum ComputeFailure: Sendable {
        /// 指定されたコンピュート関数が見つからなかった
        case functionNotFound(String)
    }

    public enum DataFailure: Sendable {
        /// ソース（ファイル・URL）の読み込みに失敗した
        case loadFailed(source: String, detail: String)
        /// JSON/CSV/TSV のパースに失敗した
        case parseFailed(detail: String)
        /// Decodable への変換に失敗した
        case decodeFailed(type: String, detail: String)
        /// Encodable からのシリアライズに失敗した
        case encodeFailed(detail: String)
        /// ファイルへの書き込みに失敗した
        case writeFailed(path: String, detail: String)
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
        case .invalidParameter(let message):
            "[metaphor] Invalid parameter: \(message)"
        case .shaderCompilationFailed(let name, let err):
            "[metaphor] Failed to compile shader '\(name)': \(err)"
        case .pipelineCreationFailed(let name, let err):
            "[metaphor] Failed to create pipeline '\(name)': \(err)"
        case .shaderNotFound(let name):
            "[metaphor] Shader function not found: '\(name)'"
        case .shaderSourceLoadFailed(let path, let detail):
            "[metaphor] Failed to read shader source '\(path)': \(detail)"
        case .canvas(let f):
            switch f {
            case .bufferCreationFailed:
                "[metaphor] Failed to create canvas vertex buffer"
            }
        case .mesh(let f):
            switch f {
            case .fileNotFound:
                "[metaphor] Mesh file not found"
            case .loadFailed(let path, let detail):
                "[metaphor] Failed to load mesh '\(path)': \(detail)"
            case .parseError(let detail):
                "[metaphor] Mesh parse error: \(detail)"
            }
        case .image(let f):
            switch f {
            case .invalidImage:
                "[metaphor] Invalid image or CGImage conversion failed"
            case .loadFailed(let source, let detail):
                "[metaphor] Failed to load image '\(source)': \(detail)"
            }
        case .font(let f):
            switch f {
            case .fileNotFound(let path):
                "[metaphor] Font file not found: '\(path)'"
            case .noFontsInFile(let path):
                "[metaphor] No fonts found in '\(path)' (unsupported format or corrupt file)"
            case .registrationFailed(let path, let detail):
                "[metaphor] Failed to register font '\(path)': \(detail)"
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
            case .fileWriteFailed(let path, let detail):
                "[metaphor] Failed to write export file '\(path)': \(detail)"
            }
        case .compute(let f):
            switch f {
            case .functionNotFound(let name):
                "[metaphor] Compute function '\(name)' not found"
            }
        case .data(let f):
            switch f {
            case .loadFailed(let source, let detail):
                "[metaphor] Failed to load data from '\(source)': \(detail)"
            case .parseFailed(let detail):
                "[metaphor] Data parse error: \(detail)"
            case .decodeFailed(let type, let detail):
                "[metaphor] Failed to decode JSON as \(type): \(detail)"
            case .encodeFailed(let detail):
                "[metaphor] Failed to encode value as JSON: \(detail)"
            case .writeFailed(let path, let detail):
                "[metaphor] Failed to write data to '\(path)': \(detail)"
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
