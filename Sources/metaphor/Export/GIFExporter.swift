@preconcurrency import Metal
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// GIF アニメーション出力エクスポーター
///
/// Metal テクスチャのフレームをキャプチャし、アニメーション GIF ファイルとして出力する。
/// SNS 共有用のジェネラティブアート出力に最適。
///
/// ```swift
/// beginGIFRecord(fps: 15)
/// // ... フレーム描画 ...
/// endGIFRecord("output.gif")
/// ```
@MainActor
public final class GIFExporter {

    // MARK: - State

    /// 録画中かどうか
    public private(set) var isRecording: Bool = false

    /// キャプチャ済みフレーム数
    public private(set) var frameCount: Int = 0

    /// フレーム間隔（秒）
    private var frameDelay: Double = 1.0 / 15.0

    /// キャプチャされたフレーム
    private var frames: [CGImage] = []

    /// ステージングテクスチャ（GPU → CPU 読み出し用）
    private var stagingTexture: MTLTexture?

    /// キャプチャする幅
    private var captureWidth: Int = 0

    /// キャプチャする高さ
    private var captureHeight: Int = 0

    // MARK: - GIF Options

    /// GIF のループ回数（0 = 無限ループ）
    public var loopCount: Int = 0

    /// ディザリングを有効にするか
    public var dithering: Bool = true

    public init() {}

    // MARK: - Public API

    /// GIF 録画を開始
    /// - Parameters:
    ///   - fps: フレームレート（デフォルト15）
    ///   - width: キャプチャ幅（ソーステクスチャの幅を使用）
    ///   - height: キャプチャ高さ
    public func beginRecord(fps: Int = 15, width: Int = 0, height: Int = 0) {
        self.frameDelay = 1.0 / Double(max(1, fps))
        self.captureWidth = width
        self.captureHeight = height
        self.frames.removeAll()
        self.frameCount = 0
        self.isRecording = true
    }

    /// 現在のフレームをキャプチャ
    /// - Parameter texture: キャプチャ対象の Metal テクスチャ
    public func captureFrame(texture: MTLTexture, device: MTLDevice) {
        guard isRecording else { return }

        let w = captureWidth > 0 ? captureWidth : texture.width
        let h = captureHeight > 0 ? captureHeight : texture.height

        // ステージングテクスチャの確保（サイズが変わったら再作成）
        if stagingTexture == nil || stagingTexture!.width != w || stagingTexture!.height != h {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: w,
                height: h,
                mipmapped: false
            )
            desc.storageMode = .managed
            desc.usage = .shaderRead
            stagingTexture = device.makeTexture(descriptor: desc)
        }

        // テクスチャからピクセルデータを読み出し
        let bytesPerRow = w * 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * h)

        texture.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: w, height: h, depth: 1)),
            mipmapLevel: 0
        )

        // BGRA → RGBA に変換
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let b = pixelData[i]
            let r = pixelData[i + 2]
            pixelData[i] = r
            pixelData[i + 2] = b
        }

        // CGImage を作成
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

    /// GIF 録画を終了してファイルに書き出し
    /// - Parameter path: 出力ファイルパス
    public func endRecord(to path: String) throws {
        guard isRecording else { return }
        isRecording = false

        guard !frames.isEmpty else {
            throw GIFExporterError.noFrames
        }

        let url = URL(fileURLWithPath: path) as CFURL

        // ディレクトリが存在しない場合は作成
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let destination = CGImageDestinationCreateWithURL(
            url,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw GIFExporterError.destinationCreationFailed
        }

        // GIF プロパティ（ループ回数）
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: loopCount
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // 各フレームを追加
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]

        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFExporterError.finalizationFailed
        }

        // メモリを解放
        frames.removeAll()
        stagingTexture = nil
    }
}

// MARK: - Errors

public enum GIFExporterError: Error, LocalizedError {
    case noFrames
    case destinationCreationFailed
    case finalizationFailed

    public var errorDescription: String? {
        switch self {
        case .noFrames:
            return "No frames captured for GIF export"
        case .destinationCreationFailed:
            return "Failed to create GIF image destination"
        case .finalizationFailed:
            return "Failed to finalize GIF file"
        }
    }
}
