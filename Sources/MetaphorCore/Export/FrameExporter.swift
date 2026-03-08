@preconcurrency import Metal
import Foundation

/// Export each frame as a sequentially numbered PNG file.
///
/// Call `beginSequence()` to start recording and `endSequence()` to stop.
/// While recording, each frame is automatically written as a PNG file.
///
/// ```swift
/// // In setup()
/// beginRecord()
///
/// // After 100 frames
/// endRecord()
/// ```
@MainActor
public final class FrameExporter {
    /// Indicate whether recording is currently in progress.
    public private(set) var isRecording: Bool = false

    /// The current frame index.
    private var frameIndex: Int = 0

    /// The output directory path.
    private var outputDirectory: String = ""

    /// The filename pattern in printf format.
    private var filenamePattern: String = "frame_%05d.png"

    public init() {}

    /// Start exporting frames as a numbered PNG sequence.
    /// - Parameters:
    ///   - directory: The output directory (created automatically if it does not exist).
    ///   - pattern: The filename pattern where `%d` is replaced with the frame number.
    public func beginSequence(directory: String, pattern: String = "frame_%05d.png") {
        self.outputDirectory = directory
        self.filenamePattern = pattern
        self.frameIndex = 0
        self.isRecording = true

        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: directory),
            withIntermediateDirectories: true
        )
    }

    /// Stop exporting frames.
    public func endSequence() {
        isRecording = false
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

        let currentFrame = frameIndex
        frameIndex += 1

        let filename = String(format: filenamePattern, currentFrame)
        let path = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename).path

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

        commandBuffer.addCompletedHandler { _ in
            MetaphorRenderer.writePNG(
                texture: stagingTexture, width: width, height: height, path: path
            )
        }
    }
}
