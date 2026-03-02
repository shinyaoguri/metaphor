@preconcurrency import Metal
import AVFoundation
import CoreVideo
import Foundation

/// ビデオコーデック
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

/// ビデオコンテナ形式
public enum VideoFormat: Sendable {
    case mp4
    case mov

    var fileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        }
    }

    /// ファイル拡張子
    public var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        }
    }
}

/// ビデオエクスポート設定
public struct VideoExportConfig: Sendable {
    /// コーデック
    public var codec: VideoCodec

    /// コンテナ形式
    public var format: VideoFormat

    /// フレームレート
    public var fps: Int

    /// ビットレート（bps）
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

/// AVFoundationを使用してスケッチ出力からMP4/MOVビデオを録画するクラス
///
/// `beginRecord()` で録画を開始し、`endRecord()` で停止する。
/// 録画中は毎フレーム自動的にビデオフレームが書き出される。
///
/// ```swift
/// // 録画開始
/// beginVideoRecord()
///
/// // 録画終了
/// endVideoRecord {
///     print("録画完了")
/// }
/// ```
@MainActor
public final class VideoExporter {
    /// 録画中かどうか
    public private(set) var isRecording: Bool = false

    /// 現在のフレームインデックス
    private var frameIndex: Int64 = 0

    /// AVAssetWriter
    private var assetWriter: AVAssetWriter?

    /// ビデオ入力
    private var writerInput: AVAssetWriterInput?

    /// ピクセルバッファアダプタ
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    /// 現在のFPS（CMTime計算用）
    private var currentFPS: Int = 60

    /// AVAssetWriter 操作を直列化するキュー
    private let writerQueue = DispatchQueue(label: "metaphor.VideoExporter.writer")

    public init() {}

    /// 録画を開始
    /// - Parameters:
    ///   - path: 出力ファイルパス
    ///   - width: ビデオ幅
    ///   - height: ビデオ高さ
    ///   - config: エクスポート設定
    public func beginRecord(
        path: String,
        width: Int,
        height: Int,
        config: VideoExportConfig = VideoExportConfig()
    ) throws {
        guard !isRecording else { return }

        let url = URL(fileURLWithPath: path)

        // ディレクトリが存在しない場合は作成
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
            throw writer.error ?? NSError(
                domain: "metaphor.VideoExporter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"]
            )
        }

        writer.startSession(atSourceTime: .zero)

        self.assetWriter = writer
        self.writerInput = input
        self.pixelBufferAdaptor = adaptor
        self.currentFPS = config.fps
        self.frameIndex = 0
        self.isRecording = true
    }

    /// 現在フレームをキャプチャ（MetaphorRenderer.renderFrame()内から呼ばれる）
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

        // Blit source → staging texture
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
            blitEncoder.synchronize(resource: stagingTexture)
            blitEncoder.endEncoding()
        }

        // Capture local copies for the @Sendable closure
        let capturedStaging = stagingTexture
        let capturedWidth = width
        let capturedHeight = height
        let queue = writerQueue

        commandBuffer.addCompletedHandler { @Sendable _ in
            queue.async {
                // Get pixel buffer from pool
                guard input.isReadyForMoreMediaData else { return }

                var pixelBuffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool else { return }

                let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return }

                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

                guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

                // Read pixels from staging texture (managed, already synchronized)
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
                adaptor.append(buffer, withPresentationTime: presentationTime)
            }
        }
    }

    /// 録画を終了
    /// - Parameter completion: 書き出し完了時に呼ばれるコールバック
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

        // writerQueue 上で markAsFinished → finishWriting を実行し、
        // 保留中の captureFrame と競合しないようにする
        writerQueue.async {
            input.markAsFinished()

            writer.finishWriting {
                DispatchQueue.main.async { [weak self] in
                    self?.assetWriter = nil
                    self?.writerInput = nil
                    self?.pixelBufferAdaptor = nil
                    self?.frameIndex = 0
                    completion?()
                }
            }
        }
    }
}
