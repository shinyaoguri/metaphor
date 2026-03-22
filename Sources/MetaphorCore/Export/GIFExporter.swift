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
@MainActor
public final class GIFExporter {

    // MARK: - State

    /// 現在記録中かどうかを示すフラグ
    public private(set) var isRecording: Bool = false

    /// これまでにキャプチャしたフレーム数
    public private(set) var frameCount: Int = 0

    /// フレーム間の遅延時間（秒）
    private var frameDelay: Double = 1.0 / 15.0

    /// キャプチャした CGImage フレームの配列
    private var frames: [CGImage] = []

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
    /// - Parameters:
    ///   - fps: フレームレート（デフォルトは15）。
    ///   - width: キャプチャ幅（0の場合はソーステクスチャの幅を使用）。
    ///   - height: キャプチャ高さ（0の場合はソーステクスチャの高さを使用）。
    public func beginRecord(fps: Int = 15, width: Int = 0, height: Int = 0) {
        self.frameDelay = 1.0 / Double(max(1, fps))
        self.captureWidth = width
        self.captureHeight = height
        self.frames.removeAll()
        self.frameCount = 0
        self.isRecording = true
    }

    /// Metal テクスチャから現在のフレームをキャプチャします。
    /// - Parameters:
    ///   - texture: キャプチャ対象の Metal テクスチャ。
    ///   - device: 必要に応じてステージングテクスチャを作成する Metal デバイス。
    ///   - commandQueue: プライベートテクスチャをCPU読み戻し用にブリットするコマンドキュー。
    public func captureFrame(texture: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) {
        guard isRecording else { return }

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

        frames.append(image)
        frameCount += 1
    }

    /// 記録を停止し、キャプチャしたフレームをGIFファイルに書き出します。
    /// - Parameter path: 出力ファイルパス。
    /// - Throws: フレームがキャプチャされていない場合、またはファイル書き込みに失敗した場合に ``MetaphorError`` をスローします。
    public func endRecord(to path: String) throws {
        guard isRecording else { return }
        isRecording = false

        guard !frames.isEmpty else {
            throw MetaphorError.export(.noFrames)
        }

        let url = URL(fileURLWithPath: path) as CFURL

        // 出力ディレクトリが存在しない場合は作成
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let destination = CGImageDestinationCreateWithURL(
            url,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw MetaphorError.export(.destinationCreationFailed)
        }

        // GIFプロパティ（ループ回数）を設定
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: loopCount
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // 各フレームをデスティネーションに追加
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]

        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw MetaphorError.export(.finalizationFailed)
        }

        // メモリを解放
        frames.removeAll()
        stagingTexture = nil
    }

    /// 記録を停止し、キャプチャしたフレームを非同期でGIFファイルに書き出します。
    ///
    /// メインスレッドをブロックしないよう、ファイル書き込みをバックグラウンドスレッドで実行します。
    /// - Parameter path: 出力ファイルパス。
    /// - Throws: フレームがキャプチャされていない場合、またはファイル書き込みに失敗した場合に ``MetaphorError`` をスローします。
    public func endRecordAsync(to path: String) async throws {
        guard isRecording else { return }
        isRecording = false

        guard !frames.isEmpty else {
            throw MetaphorError.export(.noFrames)
        }

        let capturedFrames = frames
        let capturedDelay = frameDelay
        let capturedLoopCount = loopCount
        frames.removeAll()
        frameCount = 0
        stagingTexture = nil

        try await Task.detached {
            let url = URL(fileURLWithPath: path) as CFURL
            let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            guard let destination = CGImageDestinationCreateWithURL(
                url,
                UTType.gif.identifier as CFString,
                capturedFrames.count,
                nil
            ) else {
                throw MetaphorError.export(.destinationCreationFailed)
            }

            let gifProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFLoopCount as String: capturedLoopCount
                ]
            ]
            CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: capturedDelay
                ]
            ]

            for frame in capturedFrames {
                CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
            }

            guard CGImageDestinationFinalize(destination) else {
                throw MetaphorError.export(.finalizationFailed)
            }
        }.value
    }
}
