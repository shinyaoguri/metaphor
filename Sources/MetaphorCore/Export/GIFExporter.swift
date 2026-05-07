@preconcurrency import Metal
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// キャプチャしたフレームをアニメーションGIFファイルとしてエクスポートします。
///
/// Metal テクスチャのフレームをキャプチャし、アニメーションGIFとして書き出します。
/// ジェネラティブアート作品をSNSで共有するのに最適です。
///
/// ```swift
/// beginGIFRecord(fps: 15)
/// // ... draw frames ...
/// endGIFRecord("output.gif")
/// ```
///
/// フレームは ``beginRecord(fps:width:height:)`` で開いた一時ファイルに
/// `CGImageDestination` 経由で逐次書き込まれます。これにより長時間・高解像度の
/// 録画でも `CGImage` 配列としてメモリ上に保持することはありません。
@MainActor
public final class GIFExporter {

    // MARK: - State

    /// 現在記録中かどうかを示すフラグ
    public private(set) var isRecording: Bool = false

    /// これまでにキャプチャしたフレーム数
    public private(set) var frameCount: Int = 0

    /// フレーム間の遅延時間（秒）
    private var frameDelay: Double = 1.0 / 15.0

    /// アクティブな逐次書き出し先（一時ファイル）
    private var destination: CGImageDestination?

    /// 一時ファイルの URL（`endRecord` で最終パスへ移動）
    private var temporaryURL: URL?

    /// GPU→CPU ピクセル読み戻し用のステージングテクスチャ
    private var stagingTexture: MTLTexture?

    /// キャプチャ幅（ピクセル）
    private var captureWidth: Int = 0

    /// キャプチャ高さ（ピクセル）
    private var captureHeight: Int = 0

    // MARK: - GIF Options

    /// GIFのループ回数（0は無限ループ）
    public var loopCount: Int = 0

    /// カラー量子化時のディザリング有効フラグ
    public var dithering: Bool = true

    public init() {}

    // MARK: - Public API

    /// GIF記録を開始します。
    ///
    /// 一時ファイルへの逐次書き出しが始まります。`endRecord(to:)` で最終的な
    /// 出力パスへリネームされます。途中で停止した場合は破棄してください。
    /// - Parameters:
    ///   - fps: フレームレート（デフォルトは15）。
    ///   - width: キャプチャ幅（0の場合はソーステクスチャの幅を使用）。
    ///   - height: キャプチャ高さ（0の場合はソーステクスチャの高さを使用）。
    public func beginRecord(fps: Int = 15, width: Int = 0, height: Int = 0) {
        if isRecording { abortStreaming() }

        self.frameDelay = 1.0 / Double(max(1, fps))
        self.captureWidth = width
        self.captureHeight = height
        self.frameCount = 0

        let tempName = "metaphor_gif_\(UUID().uuidString).gif"
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(tempName)
        self.temporaryURL = tempURL

        guard let dest = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            UTType.gif.identifier as CFString,
            0,  // フレーム数未確定（kCGImageDestinationLossyCompressionQuality 用に 0 でも可）
            nil
        ) else {
            self.temporaryURL = nil
            return
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: loopCount
            ]
        ]
        CGImageDestinationSetProperties(dest, gifProperties as CFDictionary)

        self.destination = dest
        self.isRecording = true
    }

    /// Metal テクスチャから現在のフレームをキャプチャします。
    /// - Parameters:
    ///   - texture: キャプチャ対象の Metal テクスチャ。
    ///   - device: 必要に応じてステージングテクスチャを作成する Metal デバイス。
    ///   - commandQueue: プライベートテクスチャをCPU読み戻し用にブリットするコマンドキュー。
    public func captureFrame(texture: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) {
        guard isRecording, let dest = destination else { return }

        let w = captureWidth > 0 ? captureWidth : texture.width
        let h = captureHeight > 0 ? captureHeight : texture.height

        // サイズが変わった場合、ステージングテクスチャを確保または再作成
        if stagingTexture == nil || stagingTexture!.width != w || stagingTexture!.height != h {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: w,
                height: h,
                mipmapped: false
            )
            desc.storageMode = .shared
            desc.usage = [.shaderRead, .shaderWrite]
            stagingTexture = device.makeTexture(descriptor: desc)
        }

        // プライベートテクスチャからステージングへブリット（CPU読み戻し用）
        let readTexture: MTLTexture
        if texture.storageMode == .private {
            guard let staging = stagingTexture,
                  let cmdBuf = commandQueue.makeCommandBuffer(),
                  let blit = cmdBuf.makeBlitCommandEncoder() else { return }
            blit.copy(from: texture, to: staging)
            blit.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            readTexture = staging
        } else {
            readTexture = texture
        }

        // （CPUアクセス可能になった）テクスチャからピクセルデータを読み取り
        let bytesPerRow = w * 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * h)

        readTexture.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: w, height: h, depth: 1)),
            mipmapLevel: 0
        )

        // BGRA → RGBA 変換
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let b = pixelData[i]
            let r = pixelData[i + 2]
            pixelData[i] = r
            pixelData[i + 2] = b
        }

        // ピクセルデータから CGImage を作成
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixelData,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let image = context.makeImage() else {
            return
        }

        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]
        CGImageDestinationAddImage(dest, image, frameProperties as CFDictionary)
        frameCount += 1
    }

    /// 記録を停止し、キャプチャしたフレームをGIFファイルに書き出します。
    /// - Parameter path: 出力ファイルパス。
    /// - Throws: フレームがキャプチャされていない場合、またはファイル書き込みに失敗した場合に ``MetaphorError`` をスローします。
    public func endRecord(to path: String) throws {
        guard isRecording else { return }
        isRecording = false

        guard let dest = destination, let tempURL = temporaryURL else {
            throw MetaphorError.export(.destinationCreationFailed)
        }
        destination = nil
        temporaryURL = nil
        stagingTexture = nil

        guard frameCount > 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw MetaphorError.export(.noFrames)
        }

        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw MetaphorError.export(.finalizationFailed)
        }

        try moveTemporaryFile(from: tempURL, to: path)
    }

    /// 記録を停止し、キャプチャしたフレームを非同期でGIFファイルに書き出します。
    ///
    /// メインスレッドをブロックしないよう、ファイナライズと最終リネームを
    /// バックグラウンドスレッドで実行します。
    /// - Parameter path: 出力ファイルパス。
    /// - Throws: フレームがキャプチャされていない場合、またはファイル書き込みに失敗した場合に ``MetaphorError`` をスローします。
    public func endRecordAsync(to path: String) async throws {
        guard isRecording else { return }
        isRecording = false

        guard let dest = destination, let tempURL = temporaryURL else {
            throw MetaphorError.export(.destinationCreationFailed)
        }
        destination = nil
        temporaryURL = nil
        stagingTexture = nil

        guard frameCount > 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw MetaphorError.export(.noFrames)
        }

        nonisolated(unsafe) let capturedDest = dest
        let capturedTempURL = tempURL

        try await Task.detached {
            guard CGImageDestinationFinalize(capturedDest) else {
                try? FileManager.default.removeItem(at: capturedTempURL)
                throw MetaphorError.export(.finalizationFailed)
            }
            try Self.moveTemporaryFileNonisolated(from: capturedTempURL, to: path)
        }.value
    }

    // MARK: - Private

    private func moveTemporaryFile(from tempURL: URL, to path: String) throws {
        try Self.moveTemporaryFileNonisolated(from: tempURL, to: path)
    }

    nonisolated private static func moveTemporaryFileNonisolated(from tempURL: URL, to path: String) throws {
        let destURL = URL(fileURLWithPath: path)
        let dir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)
    }

    private func abortStreaming() {
        destination = nil
        if let tempURL = temporaryURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        temporaryURL = nil
        stagingTexture = nil
        isRecording = false
        frameCount = 0
    }
}
