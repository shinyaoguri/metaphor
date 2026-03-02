@preconcurrency import Metal
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Export captured frames as an animated GIF file.
///
/// Capture Metal texture frames and write them out as an animated GIF.
/// Ideal for sharing generative art output on social media.
///
/// ```swift
/// beginGIFRecord(fps: 15)
/// // ... draw frames ...
/// endGIFRecord("output.gif")
/// ```
@MainActor
public final class GIFExporter {

    // MARK: - State

    /// Indicate whether recording is currently in progress.
    public private(set) var isRecording: Bool = false

    /// Return the number of frames captured so far.
    public private(set) var frameCount: Int = 0

    /// The delay between frames in seconds.
    private var frameDelay: Double = 1.0 / 15.0

    /// The array of captured CGImage frames.
    private var frames: [CGImage] = []

    /// Staging texture for GPU-to-CPU pixel readback.
    private var stagingTexture: MTLTexture?

    /// The capture width in pixels.
    private var captureWidth: Int = 0

    /// The capture height in pixels.
    private var captureHeight: Int = 0

    // MARK: - GIF Options

    /// The number of times the GIF loops (0 means infinite loop).
    public var loopCount: Int = 0

    /// Whether dithering is enabled for color quantization.
    public var dithering: Bool = true

    public init() {}

    // MARK: - Public API

    /// Start GIF recording.
    /// - Parameters:
    ///   - fps: The frame rate (default is 15).
    ///   - width: The capture width (uses source texture width if 0).
    ///   - height: The capture height (uses source texture height if 0).
    public func beginRecord(fps: Int = 15, width: Int = 0, height: Int = 0) {
        self.frameDelay = 1.0 / Double(max(1, fps))
        self.captureWidth = width
        self.captureHeight = height
        self.frames.removeAll()
        self.frameCount = 0
        self.isRecording = true
    }

    /// Capture the current frame from a Metal texture.
    /// - Parameters:
    ///   - texture: The Metal texture to capture.
    ///   - device: The Metal device used to create the staging texture if needed.
    public func captureFrame(texture: MTLTexture, device: MTLDevice) {
        guard isRecording else { return }

        let w = captureWidth > 0 ? captureWidth : texture.width
        let h = captureHeight > 0 ? captureHeight : texture.height

        // Allocate or recreate the staging texture if the size changed
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

        // Read pixel data from the texture
        let bytesPerRow = w * 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * h)

        texture.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: w, height: h, depth: 1)),
            mipmapLevel: 0
        )

        // Convert BGRA to RGBA
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let b = pixelData[i]
            let r = pixelData[i + 2]
            pixelData[i] = r
            pixelData[i + 2] = b
        }

        // Create a CGImage from the pixel data
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

    /// Stop recording and write the captured frames to a GIF file.
    /// - Parameter path: The output file path.
    /// - Throws: `GIFExporterError` if no frames were captured or the file could not be written.
    public func endRecord(to path: String) throws {
        guard isRecording else { return }
        isRecording = false

        guard !frames.isEmpty else {
            throw GIFExporterError.noFrames
        }

        let url = URL(fileURLWithPath: path) as CFURL

        // Create the output directory if it does not exist
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

        // Set GIF properties (loop count)
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: loopCount
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Add each frame to the destination
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

        // Release memory
        frames.removeAll()
        stagingTexture = nil
    }
}

// MARK: - Errors

/// Represent errors that can occur during GIF export.
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
