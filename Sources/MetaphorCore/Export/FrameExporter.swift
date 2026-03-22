@preconcurrency import Metal
import Foundation

/// 各フレームを連番PNGファイルとしてエクスポートします。
///
/// `beginSequence()` で記録を開始し、`endSequence()` で停止します。
/// 記録中は各フレームが自動的にPNGファイルとして書き出されます。
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
    /// 現在記録中かどうかを示すフラグ
    public private(set) var isRecording: Bool = false

    /// 現在のフレームインデックス
    private var frameIndex: Int = 0

    /// 出力ディレクトリパス
    private var outputDirectory: String = ""

    /// printf形式のファイル名パターン
    private var filenamePattern: String = "frame_%05d.png"

    public init() {}

    /// フレームの連番PNGシーケンスのエクスポートを開始します。
    /// - Parameters:
    ///   - directory: 出力ディレクトリ（存在しない場合は自動作成されます）。
    ///   - pattern: ファイル名パターン。`%d` がフレーム番号に置換されます。
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

    /// フレームのエクスポートを停止します。
    public func endSequence() {
        isRecording = false
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
