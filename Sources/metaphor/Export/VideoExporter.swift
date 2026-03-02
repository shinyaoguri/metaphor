@preconcurrency import Metal
import AVFoundation
import CoreVideo
import Foundation
import os

/// A simple thread-safe boolean flag for cross-queue coordination.
private final class AtomicFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var value: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

/// Represent the video codec to use for encoding.
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

/// Represent the container format for video output.
public enum VideoFormat: Sendable {
    case mp4
    case mov

    var fileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        }
    }

    /// Return the file extension string for this format.
    public var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        }
    }
}

/// Configure video export parameters.
public struct VideoExportConfig: Sendable {
    /// The video codec to use.
    public var codec: VideoCodec

    /// The container format for the output file.
    public var format: VideoFormat

    /// The target frame rate in frames per second.
    public var fps: Int

    /// The target bitrate in bits per second.
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

/// Record MP4/MOV video from sketch output using AVFoundation.
///
/// Call `beginRecord()` to start recording and `endRecord()` to stop.
/// While recording, each frame is automatically written to the video file.
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
    /// Indicate whether recording is currently in progress.
    public private(set) var isRecording: Bool = false

    /// The current frame index.
    private var frameIndex: Int64 = 0

    /// The AVAssetWriter for the current recording session.
    private var assetWriter: AVAssetWriter?

    /// The video writer input.
    private var writerInput: AVAssetWriterInput?

    /// The pixel buffer adaptor for appending frames.
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    /// The current frame rate used for CMTime calculations.
    private var currentFPS: Int = 60

    /// Serial dispatch queue to serialize AVAssetWriter operations.
    private let writerQueue = DispatchQueue(label: "metaphor.VideoExporter.writer")

    /// Thread-safe flag to reject late frames after endRecord (accessed only from writerQueue).
    private let endingFlag = AtomicFlag()

    public init() {}

    /// Start recording to a video file.
    /// - Parameters:
    ///   - path: The output file path.
    ///   - width: The video width in pixels.
    ///   - height: The video height in pixels.
    ///   - config: The export configuration.
    /// - Throws: An error if the writer cannot be created or started.
    public func beginRecord(
        path: String,
        width: Int,
        height: Int,
        config: VideoExportConfig = VideoExportConfig()
    ) throws {
        guard !isRecording else { return }

        let url = URL(fileURLWithPath: path)

        // Create the output directory if it does not exist
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Remove existing file if present
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

    /// Capture the current frame (called from MetaphorRenderer.renderFrame()).
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

        // Blit source -> staging texture
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

        let flag = endingFlag

        commandBuffer.addCompletedHandler { @Sendable _ in
            queue.async {
                // Reject frames arriving after endRecord was called
                guard !flag.value else { return }
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

    /// Stop recording and finalize the video file.
    /// - Parameter completion: An optional callback invoked on the main thread when writing completes.
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

        // Set the ending flag synchronously on the writer queue.
        // This ensures all previously enqueued frame writes complete first,
        // then the flag prevents any late-arriving frames from being written.
        writerQueue.sync {
            flag.value = true
        }

        // Finalize the video file on the writer queue
        writerQueue.async {
            input.markAsFinished()

            writer.finishWriting {
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
}
