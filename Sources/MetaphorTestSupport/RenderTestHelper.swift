import Metal
import MetaphorCore

/// Helper for offscreen rendering and pixel readback in tests.
///
/// Creates a minimal render environment and provides pixel-level verification.
///
/// ```swift
/// var helper = try RenderTestHelper(width: 64, height: 64)
/// try helper.render { canvas in
///     canvas.background(.white)
/// }
/// let pixel = helper.readPixel(x: 32, y: 32)
/// #expect(pixel.r > 200)
/// ```
@MainActor
public struct RenderTestHelper {

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let canvas: Canvas2D
    public let textureManager: TextureManager
    public let width: Int
    public let height: Int

    /// Staging texture for GPU→CPU readback (managed storage).
    private let stagingTexture: MTLTexture

    /// Raw pixel data after readback (BGRA8).
    private var pixelData: [UInt8]

    public struct Pixel {
        public let r: UInt8
        public let g: UInt8
        public let b: UInt8
        public let a: UInt8
    }

    public init(width: Int = 64, height: Int = 64) throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw MetaphorError.deviceNotAvailable
        }
        self.device = dev
        guard let queue = dev.makeCommandQueue() else {
            throw MetaphorError.deviceNotAvailable
        }
        self.commandQueue = queue
        self.width = width
        self.height = height

        let shaderLib = try ShaderLibrary(device: dev)
        let depthCache = DepthStencilCache(device: dev)

        self.textureManager = try TextureManager(
            device: dev,
            width: width,
            height: height,
            sampleCount: 1
        )

        self.canvas = try Canvas2D(
            device: dev,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: Float(width),
            height: Float(height),
            sampleCount: 1
        )

        // Create managed staging texture for readback
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let staging = dev.makeTexture(descriptor: desc) else {
            throw MetaphorError.textureCreationFailed(width: width, height: height, format: "staging")
        }
        self.stagingTexture = staging
        self.pixelData = [UInt8](repeating: 0, count: width * height * 4)
    }

    /// Set the clear color for the next render pass.
    public func setClearColor(r: Double, g: Double, b: Double, a: Double = 1.0) {
        textureManager.setClearColor(MTLClearColor(red: r, green: g, blue: b, alpha: a))
    }

    /// Render a frame using the provided draw closure, then blit to staging for readback.
    ///
    /// Note: Canvas2D `background()` relies on `onSetClearColor` callback which is
    /// set up by MetaphorRenderer. In test mode, use `setClearColor()` before `render()`
    /// to control the clear color, and use drawing commands inside the closure.
    public mutating func render(_ draw: (Canvas2D) -> Void) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let rpd = textureManager.renderPassDescriptor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }

        canvas.begin(encoder: encoder)
        draw(canvas)
        canvas.flush()
        canvas.end()
        encoder.endEncoding()

        // Blit from private color texture to managed staging texture
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(
                from: textureManager.colorTexture,
                sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: stagingTexture,
                destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read pixels from staging texture
        stagingTexture.getBytes(
            &pixelData,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
    }

    /// Read a pixel at the given coordinates (BGRA→RGBA converted).
    public func readPixel(x: Int, y: Int) -> Pixel {
        let offset = (y * width + x) * 4
        return Pixel(
            r: pixelData[offset + 2],  // BGRA → R
            g: pixelData[offset + 1],  // BGRA → G
            b: pixelData[offset + 0],  // BGRA → B
            a: pixelData[offset + 3]   // BGRA → A
        )
    }

    /// Check if a region has any non-zero (non-black) pixels.
    public func hasNonBlackPixels(inRect x: Int, y: Int, width w: Int, height h: Int) -> Bool {
        for py in y..<(y + h) {
            for px in x..<(x + w) {
                let p = readPixel(x: px, y: py)
                if p.r > 0 || p.g > 0 || p.b > 0 {
                    return true
                }
            }
        }
        return false
    }

    /// Average color of a region.
    public func averageColor(inRect x: Int, y: Int, width w: Int, height h: Int) -> (r: Float, g: Float, b: Float, a: Float) {
        var totalR: Float = 0
        var totalG: Float = 0
        var totalB: Float = 0
        var totalA: Float = 0
        let count = Float(w * h)

        for py in y..<(y + h) {
            for px in x..<(x + w) {
                let p = readPixel(x: px, y: py)
                totalR += Float(p.r) / 255.0
                totalG += Float(p.g) / 255.0
                totalB += Float(p.b) / 255.0
                totalA += Float(p.a) / 255.0
            }
        }

        return (totalR / count, totalG / count, totalB / count, totalA / count)
    }
}
