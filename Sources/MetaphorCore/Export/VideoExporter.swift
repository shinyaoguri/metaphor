@preconcurrency import Metal
@preconcurrency import AVFoundation
import CoreVideo
import Foundation

/// ビデオエンコードに使用するコーデック
public enum VideoCodec: Sendable {
    case h264
    case h265

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .h265: return .hevc
        }
    }
}

/// ビデオ出力のコンテナフォーマット
public enum VideoFormat: Sendable {
    case mp4
    case mov

    var fileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        }
    }

    /// このフォーマットのファイル拡張子文字列
    public var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        }
    }
}

/// ビデオエクスポートのパラメータ設定
public struct VideoExportConfig: Sendable {
    /// 使用するビデオコーデック
    public var codec: VideoCodec

    /// 出力ファイルのコンテナフォーマット
    public var format: VideoFormat

    /// 目標フレームレート（fps）
    public var fps: Int

    /// 目標ビットレート（bps）
    public var bitrate: Int

    public init(
        codec: VideoCodec = .h264,
        format: VideoFormat = .mp4,
        fps: Int = 60,
        bitrate: Int = 10_000_000
    ) {
        self.codec = codec
        self.format = format
        self.fps = fps
        self.bitrate = bitrate
    }
}

/// AVFoundation を使用してスケッチ出力から MP4/MOV ビデオを記録します。
///
/// `beginRecord()` で記録を開始し、`endRecord()` で停止します。
/// 記録中は各フレームが自動的にビデオファイルに書き込まれます。
///
/// ```swift
/// // Start recording
/// beginVideoRecord()
///
/// // Stop recording
/// endVideoRecord {
///     print("Recording complete")
/// }
/// ```
@MainActor
public final class VideoExporter {
    /// 現在記録中かどうかを示すフラグ
    public private(set) var isRecording: Bool = false

    /// 現在のフレームインデックス
    private var frameIndex: Int64 = 0

    /// ライターのバックプレッシャ等で書き込めずドロップしたフレーム数。
    ///
    /// `frameIndex` は常に進むため出力動画のタイムスタンプは保たれますが、
    /// ドロップが起きると該当時刻の絵が抜けます。録画品質の判断材料として参照してください。
    public private(set) var droppedFrameCount: Int = 0

    /// 各ドロップ発生時に呼び出されるオプションコールバック。
    ///
    /// MainActor で呼ばれます。引数は失われたフレームの `frameIndex` です。
    public var onFrameDropped: (@MainActor (Int64) -> Void)?

    /// 直近の記録セッションで発生した書き込みエラー。成功時は `nil`。
    ///
    /// `endRecord` の completion が呼ばれた時点で確定しています。壊れたファイルが
    /// 成功扱いにならないよう、録画完了後にこの値を確認してください。
    ///
    /// **現行セッションのみ**に反映されます。`endRecord` 直後に `beginRecord` した場合、
    /// 旧セッションのファイナライズ失敗はこの値を汚染せず、``onError`` でのみ観測できます。
    public private(set) var lastError: Error?

    /// ファイナライズ失敗時に呼び出されるオプションコールバック（MainActor）。
    public var onError: (@MainActor (Error) -> Void)?

    /// 現在の記録セッション用の AVAssetWriter
    private var assetWriter: AVAssetWriter?

    /// ビデオライター入力
    private var writerInput: AVAssetWriterInput?

    /// フレーム追加用のピクセルバッファアダプタ
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    /// CMTime 計算に使用する現在のフレームレート
    private var currentFPS: Int = 60

    /// AVAssetWriter 操作を直列化するためのディスパッチキュー
    private let writerQueue = DispatchQueue(label: "metaphor.VideoExporter.writer")

    /// インフライト中のフレーム書き込みを追跡するためのディスパッチグループ。
    /// `captureFrame` で `enter()`、完了ハンドラの末尾で `leave()` するため、
    /// `endRecord` は `notify` で全フレーム書き込み完了後にファイナライズできます。
    ///
    /// セッションごとに `beginRecord` で新規作成します。共有のままだと、旧セッションの
    /// `notify` 待機中に次の録画の `enter()` が発火を先送りし、連続録画で旧ファイルの
    /// ファイナライズが実質保留になるためです。
    private var pendingWrites = DispatchGroup()

    public init() {}

    /// ビデオファイルへの記録を開始します。
    /// - Parameters:
    ///   - path: 出力ファイルパス。
    ///   - width: ビデオの幅（ピクセル）。
    ///   - height: ビデオの高さ（ピクセル）。
    ///   - config: エクスポート設定。
    /// - Throws: ライターの作成または開始に失敗した場合にエラーをスローします。
    public func beginRecord(
        path: String,
        width: Int,
        height: Int,
        config: VideoExportConfig = VideoExportConfig()
    ) throws {
        guard !isRecording else { return }

        let url = URL(fileURLWithPath: path)

        // 出力ディレクトリが存在しない場合は作成
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 既存ファイルがあれば削除
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: config.format.fileType)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: config.codec.avCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.bitrate
            ]
        ]

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        input.expectsMediaDataInRealTime = false

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? MetaphorError.export(.writerFailed("Failed to start writing"))
        }

        writer.startSession(atSourceTime: .zero)

        self.assetWriter = writer
        self.writerInput = input
        self.pixelBufferAdaptor = adaptor
        if config.fps <= 0 {
            metaphorWarning("VideoExporter: fps must be positive (got \(config.fps)); clamping to 1")
        }
        self.currentFPS = max(1, config.fps)
        self.frameIndex = 0
        self.droppedFrameCount = 0
        self.lastError = nil
        self.pendingWrites = DispatchGroup()
        self.isRecording = true
    }

    /// writerQueue で発生したドロップを MainActor に反映するヘルパー。
    /// `weak self` 経由で呼ぶことで、エクスポータが先に解放されてもクラッシュしません。
    ///
    /// `sessionID`（そのフレームが属するセッションの writer の同一性）が現行セッションと
    /// 一致するときだけ反映します。end→begin を素早く呼ぶと、旧セッションの遅延到着
    /// ドロップが新セッションの `droppedFrameCount` / `onFrameDropped` を汚染するためです
    /// （旧セッションは既にファイナライズ済みで、報告しても意味を持たない）。
    nonisolated private static func recordDrop(
        _ exporter: VideoExporter?, sessionID: ObjectIdentifier, frameIndex: Int64
    ) {
        Task { @MainActor in
            guard let exporter,
                  let writer = exporter.assetWriter,
                  ObjectIdentifier(writer) == sessionID else { return }
            exporter.droppedFrameCount += 1
            exporter.onFrameDropped?(frameIndex)
        }
    }

    /// 現在のフレームをキャプチャします（MetaphorRenderer.renderFrame() から呼ばれます）。
    func captureFrame(
        sourceTexture: MTLTexture,
        stagingTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        width: Int,
        height: Int,
        completionGroup: DispatchGroup? = nil
    ) {
        guard isRecording else { return }
        guard let adaptor = pixelBufferAdaptor,
              let input = writerInput,
              let writer = assetWriter else { return }

        // このフレームが属するセッションの識別子。遅延到着するドロップ報告を
        // 現行セッションと突き合わせるために完了ハンドラへ渡す。
        let sessionID = ObjectIdentifier(writer)

        let currentFrame = frameIndex
        frameIndex += 1
        let fps = Int32(currentFPS)

        // ソース → ステージングテクスチャへブリット
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(
                from: sourceTexture,
                sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: stagingTexture,
                destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
        }

        // @Sendable クロージャ用にローカルコピーをキャプチャ
        let capturedStaging = stagingTexture
        let capturedWidth = width
        let capturedHeight = height
        let queue = writerQueue
        let group = pendingWrites

        // これらのキャプチャは安全: すべてのアクセスは writerQueue で直列化されます。
        nonisolated(unsafe) let capturedInput = input
        nonisolated(unsafe) let capturedAdaptor = adaptor

        // インフライト書き込みとして登録。完了ハンドラ末尾で必ず `leave()` する。
        // これにより `endRecord` は GPU 側の遅延到着フレームも待ってからファイナライズできる。
        group.enter()
        completionGroup?.enter()
        commandBuffer.addCompletedHandler { @Sendable [weak self] _ in
            queue.async {
                defer {
                    completionGroup?.leave()
                    group.leave()
                }
                // 非リアルタイム録画（expectsMediaDataInRealTime = false）なので、
                // ready でなければ待つ。即ドロップするとオフライン録画でも絵が抜ける。
                // ハング回避のため上限（約 2 秒）つき。
                var waitBudget = 1000
                while !capturedInput.isReadyForMoreMediaData && waitBudget > 0 {
                    usleep(2000)  // 2ms
                    waitBudget -= 1
                }
                guard capturedInput.isReadyForMoreMediaData else {
                    Self.recordDrop(self, sessionID: sessionID, frameIndex: currentFrame)
                    return
                }

                var pixelBuffer: CVPixelBuffer?
                guard let pool = capturedAdaptor.pixelBufferPool else {
                    Self.recordDrop(self, sessionID: sessionID, frameIndex: currentFrame)
                    return
                }

                let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                    Self.recordDrop(self, sessionID: sessionID, frameIndex: currentFrame)
                    return
                }

                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

                guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
                    Self.recordDrop(self, sessionID: sessionID, frameIndex: currentFrame)
                    return
                }
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

                // ステージングテクスチャからピクセルを読み取り（shared、ユニファイドメモリによりコヒーレント）
                capturedStaging.getBytes(
                    baseAddress,
                    bytesPerRow: bytesPerRow,
                    from: MTLRegionMake2D(0, 0, capturedWidth, capturedHeight),
                    mipmapLevel: 0
                )

                let presentationTime = CMTime(
                    value: currentFrame,
                    timescale: fps
                )
                if !capturedAdaptor.append(buffer, withPresentationTime: presentationTime) {
                    // 書き込み失敗もドロップとして計上する（従来は黙殺されていた）
                    Self.recordDrop(self, sessionID: sessionID, frameIndex: currentFrame)
                }
            }
        }
    }

    /// 記録を停止し、ビデオファイルをファイナライズします。
    /// - Parameter completion: 書き込み完了時にメインスレッドで呼び出されるオプションのコールバック。
    public func endRecord(completion: (@Sendable () -> Void)? = nil) {
        guard isRecording else {
            completion?()
            return
        }

        isRecording = false

        guard let writer = assetWriter,
              let input = writerInput else {
            completion?()
            return
        }

        // これらのキャプチャは安全: すべてのアクセスは writerQueue で直列化されます。
        nonisolated(unsafe) let capturedInput = input
        nonisolated(unsafe) let capturedWriter = writer

        // インフライト中のフレーム書き込み（GPU 完了を待っている、または writerQueue
        // 上のジョブを待っている）が全て終わってからファイナライズする。
        // `isRecording = false` 以降に新たな `enter()` は発生しないため、
        // `notify` は確実に発火する。
        pendingWrites.notify(queue: writerQueue) {
            capturedInput.markAsFinished()

            capturedWriter.finishWriting {
                // 書き込み失敗（.failed / .cancelled）でも従来は成功と同じ completion が
                // 呼ばれ、壊れたファイルが成功扱いになっていた。status を検証して
                // lastError / onError で観測可能にする。
                let finishError: Error?
                if capturedWriter.status == .completed {
                    finishError = nil
                } else {
                    finishError = capturedWriter.error
                        ?? MetaphorError.export(.writerFailed(
                            "finishWriting ended with status \(capturedWriter.status.rawValue)"
                        ))
                }

                Task { @MainActor [weak self] in
                    // 旧セッションのファイナライズ完了は、自分が起こしたセッションの
                    // 状態にしか触れてはならない。end→begin を素早く呼ぶと、ここに
                    // 到達した時点で既に新しい録画セッションが共有プロパティを差し替え
                    // ている場合があり、無条件に書くと新セッションを壊してしまう。
                    // writer の同一性を確認し、まだ現行セッションのときだけ
                    // 参照のクリアと lastError の反映を行う。
                    let isCurrentSession = self?.assetWriter === capturedWriter
                    if let self, isCurrentSession {
                        self.assetWriter = nil
                        self.writerInput = nil
                        self.pixelBufferAdaptor = nil
                        self.frameIndex = 0
                    }
                    if let finishError {
                        metaphorWarning("VideoExporter: finishWriting failed: \(finishError)")
                        if let self {
                            if isCurrentSession {
                                self.lastError = finishError
                            }
                            // どのセッションの失敗かに関わらずイベントとしては通知する
                            //（旧セッションの失敗も観測可能に保つ）
                            self.onError?(finishError)
                        }
                    }
                    completion?()
                }
            }
        }
    }

    /// 記録を停止し、ビデオファイルを非同期でファイナライズします。
    ///
    /// ``endRecord(completion:)`` の async/await 版です。
    public func endRecord() async {
        guard isRecording else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            endRecord {
                continuation.resume()
            }
        }
    }
}
