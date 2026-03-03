import Testing
import CoreML
import CoreVideo
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - MLTextureConverter Tests

@Suite("MLTextureConverter", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MLTextureConverterTests {

    @Test("pixelBuffer from shared texture")
    func pixelBufferFromShared() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let texture = device.makeTexture(descriptor: desc)!

        // Fill with solid red (BGRA: 0, 0, 255, 255)
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 0       // B
            pixels[i + 1] = 0   // G
            pixels[i + 2] = 255 // R
            pixels[i + 3] = 255 // A
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, 4, 4),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: 4 * 4
        )

        let pb = converter.pixelBuffer(from: texture)
        #expect(pb != nil)
        if let pb = pb {
            #expect(CVPixelBufferGetWidth(pb) == 4)
            #expect(CVPixelBufferGetHeight(pb) == 4)
        }
    }

    @Test("texture from CVPixelBuffer round-trip")
    func textureFromPixelBuffer() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        // Create a CVPixelBuffer
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferCreate(nil, 8, 8, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        #expect(pixelBuffer != nil)

        if let pb = pixelBuffer {
            let tex = converter.texture(from: pb)
            #expect(tex != nil)
            #expect(tex?.width == 8)
            #expect(tex?.height == 8)
        }
    }

    @Test("cgImage round-trip")
    func cgImageRoundTrip() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        // Create a simple CGImage
        let width = 4
        let height = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create CGContext")
            return
        }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else {
            Issue.record("Failed to create CGImage")
            return
        }

        let tex = converter.texture(from: cgImage)
        #expect(tex != nil)
        #expect(tex?.width == 4)
        #expect(tex?.height == 4)

        if let tex = tex {
            let roundTrip = converter.cgImage(from: tex)
            #expect(roundTrip != nil)
            #expect(roundTrip?.width == 4)
            #expect(roundTrip?.height == 4)
        }
    }
}

// MARK: - SketchContext MLTextureConverter Factory Test

@Suite("SketchContext MLTextureConverter", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SketchContextMLTextureConverterTests {

    @Test("createMLTextureConverter returns valid instance")
    func createMLTextureConverter() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let ctx = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        let converter = ctx.createMLTextureConverter()
        // Converter should be functional
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 2, height: 2, mipmapped: false)
        desc.storageMode = .shared
        let tex = renderer.device.makeTexture(descriptor: desc)!
        let pb = converter.pixelBuffer(from: tex)
        #expect(pb != nil)
    }
}
