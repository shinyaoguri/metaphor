@preconcurrency import Metal
@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import os

/// スレッドセーフな真偽値フラグ（キュー間の協調用）
private final class AtomicFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var value: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

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

    /// endRecord 後の遅延フレームを拒否するためのスレッドセーフフラグ（writerQueue からのみアクセス）
    private let endingFlag = AtomicFlag()

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
        self.currentFPS = config.fps
        self.frameIndex = 0
        self.isRecording = true
    }

    /// 現在のフレームをキャプチャします（MetaphorRenderer.renderFrame() から呼ばれます）。
    func captureFrame(
        sourceTexture: MTLTexture,
        stagingTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        width: Int,
        height: Int
    ) {
        guard isRecording else { return }
        guard let adaptor = pixelBufferAdaptor,
              let input = writerInput else { return }

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

        let flag = endingFlag

        // これらのキャプチャは安全: すべてのアクセスは writerQueue で直列化されます。
        nonisolated(unsafe) let capturedInput = input
        nonisolated(unsafe) let capturedAdaptor = adaptor

        commandBuffer.addCompletedHandler { @Sendable _ in
            queue.async {
                // endRecord 後に到着したフレームを拒否
                guard !flag.value else { return }
                // プールからピクセルバッファを取得
                guard capturedInput.isReadyForMoreMediaData else { return }

                var pixelBuffer: CVPixelBuffer?
                guard let pool = capturedAdaptor.pixelBufferPool else { return }

                let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return }

                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

                guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }
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
                capturedAdaptor.append(buffer, withPresentationTime: presentationTime)
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

        let flag = endingFlag

        // writerQueue 上で同期的に終了フラグを設定。
        // これにより、先にエンキューされたすべてのフレーム書き込みが完了してから
        // フラグが設定され、遅延到着フレームの書き込みが防止されます。
        writerQueue.sync {
            flag.value = true
        }

        // これらのキャプチャは安全: すべてのアクセスは writerQueue で直列化されます。
        nonisolated(unsafe) let capturedInput = input
        nonisolated(unsafe) let capturedWriter = writer

        // writerQueue 上でビデオファイルをファイナライズ
        writerQueue.async {
            capturedInput.markAsFinished()

            capturedWriter.finishWriting {
                Task { @MainActor [weak self] in
                    self?.assetWriter = nil
                    self?.writerInput = nil
                    self?.pixelBufferAdaptor = nil
                    self?.frameIndex = 0
                    flag.value = false
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
