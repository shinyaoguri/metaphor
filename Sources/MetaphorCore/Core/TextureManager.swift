import Metal

/// Manages offscreen render target textures for the two-pass rendering system.
///
/// `TextureManager` creates and holds the color, depth, and optional MSAA textures
/// used for offscreen rendering. It follows an immutable design — resizing creates
/// a new instance rather than mutating the existing one.
///
/// ```swift
/// let textures = try TextureManager(device: device, width: 1920, height: 1080)
/// ```
public final class TextureManager {
    /// The Metal device used to create textures.
    public let device: MTLDevice

    /// The resolved color texture (render target when MSAA is disabled).
    public private(set) var colorTexture: MTLTexture

    /// MSAA multisampled color texture (only present when MSAA is enabled).
    private var msaaColorTexture: MTLTexture?

    /// MSAA multisampled depth texture (only present when MSAA is enabled).
    private var msaaDepthTexture: MTLTexture?

    /// The depth texture for depth testing.
    public private(set) var depthTexture: MTLTexture

    /// The render pass descriptor configured for the managed textures.
    public private(set) var renderPassDescriptor: MTLRenderPassDescriptor

    /// The width of the managed textures in pixels.
    public let width: Int

    /// The height of the managed textures in pixels.
    public let height: Int

    /// The MSAA sample count (1 = disabled, 4 = 4x MSAA).
    public let sampleCount: Int

    /// The aspect ratio of the managed textures (width / height).
    public var aspectRatio: Float {
        Float(width) / Float(height)
    }

    /// Creates a new texture manager with the specified dimensions.
    ///
    /// - Parameters:
    ///   - device: The Metal device to use for texture creation.
    ///   - width: The texture width in pixels.
    ///   - height: The texture height in pixels.
    ///   - pixelFormat: The color texture pixel format.
    ///   - depthFormat: The depth texture pixel format.
    ///   - clearColor: The clear color for the render pass.
    ///   - sampleCount: The MSAA sample count. Falls back to 1 if unsupported by the device.
    /// - Throws: ``MetaphorError/textureCreationFailed(width:height:format:)`` if any texture cannot be created.
    public init(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .depth32Float,
        clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1),
        sampleCount: Int = 4
    ) throws {
        self.device = device
        self.width = width
        self.height = height

        // Validate sample count: fall back to 1 if the device does not support it
        if sampleCount > 1 && !device.supportsTextureSampleCount(sampleCount) {
            metaphorWarning("sampleCount \(sampleCount) is not supported by this device. Falling back to 1.")
            self.sampleCount = 1
        } else {
            self.sampleCount = sampleCount
        }

        // Color texture (resolve target / render target when MSAA is disabled)
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        guard let colorTex = device.makeTexture(descriptor: colorDescriptor) else {
            throw MetaphorError.textureCreationFailed(width: width, height: height, format: "color")
        }
        self.colorTexture = colorTex

        // Depth texture
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        guard let depthTex = device.makeTexture(descriptor: depthDescriptor) else {
            throw MetaphorError.textureCreationFailed(width: width, height: height, format: "depth")
        }
        self.depthTexture = depthTex

        // MSAA textures
        if sampleCount > 1 {
            let msaaColorDesc = MTLTextureDescriptor()
            msaaColorDesc.textureType = .type2DMultisample
            msaaColorDesc.pixelFormat = pixelFormat
            msaaColorDesc.width = width
            msaaColorDesc.height = height
            msaaColorDesc.sampleCount = sampleCount
            msaaColorDesc.usage = .renderTarget
            msaaColorDesc.storageMode = .private
            guard let msaaColorTex = device.makeTexture(descriptor: msaaColorDesc) else {
                throw MetaphorError.textureCreationFailed(width: width, height: height, format: "msaaColor")
            }
            msaaColorTexture = msaaColorTex

            let msaaDepthDesc = MTLTextureDescriptor()
            msaaDepthDesc.textureType = .type2DMultisample
            msaaDepthDesc.pixelFormat = depthFormat
            msaaDepthDesc.width = width
            msaaDepthDesc.height = height
            msaaDepthDesc.sampleCount = self.sampleCount
            msaaDepthDesc.usage = .renderTarget
            msaaDepthDesc.storageMode = .private
            guard let msaaDepthTex = device.makeTexture(descriptor: msaaDepthDesc) else {
                throw MetaphorError.textureCreationFailed(width: width, height: height, format: "msaaDepth")
            }
            msaaDepthTexture = msaaDepthTex
        }

        // Render pass descriptor
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].clearColor = clearColor
        rpd.colorAttachments[0].loadAction = .clear
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1.0

        if sampleCount > 1 {
            // MSAA: render to multisample texture, resolve to colorTexture
            rpd.colorAttachments[0].texture = msaaColorTexture
            rpd.colorAttachments[0].resolveTexture = colorTexture
            rpd.colorAttachments[0].storeAction = .multisampleResolve
            rpd.depthAttachment.texture = msaaDepthTexture
        } else {
            // No MSAA: render directly to colorTexture
            rpd.colorAttachments[0].texture = colorTexture
            rpd.colorAttachments[0].storeAction = .store
            rpd.depthAttachment.texture = depthTexture
        }
        self.renderPassDescriptor = rpd
    }

    /// Creates a Full HD (1920x1080) texture manager.
    ///
    /// - Parameters:
    ///   - device: The Metal device.
    ///   - clearColor: The clear color.
    ///   - sampleCount: The MSAA sample count.
    /// - Returns: A new `TextureManager` configured for 1920x1080.
    public static func fullHD(device: MTLDevice, clearColor: MTLClearColor = .black, sampleCount: Int = 4) throws -> TextureManager {
        try TextureManager(device: device, width: 1920, height: 1080, clearColor: clearColor, sampleCount: sampleCount)
    }

    /// Creates a 4K UHD (3840x2160) texture manager.
    ///
    /// - Parameters:
    ///   - device: The Metal device.
    ///   - clearColor: The clear color.
    ///   - sampleCount: The MSAA sample count.
    /// - Returns: A new `TextureManager` configured for 3840x2160.
    public static func uhd4K(device: MTLDevice, clearColor: MTLClearColor = .black, sampleCount: Int = 4) throws -> TextureManager {
        try TextureManager(device: device, width: 3840, height: 2160, clearColor: clearColor, sampleCount: sampleCount)
    }

    /// Creates a square texture manager with the specified size.
    ///
    /// - Parameters:
    ///   - device: The Metal device.
    ///   - size: The width and height in pixels.
    ///   - clearColor: The clear color.
    ///   - sampleCount: The MSAA sample count.
    /// - Returns: A new `TextureManager` with equal width and height.
    public static func square(device: MTLDevice, size: Int, clearColor: MTLClearColor = .black, sampleCount: Int = 4) throws -> TextureManager {
        try TextureManager(device: device, width: size, height: size, clearColor: clearColor, sampleCount: sampleCount)
    }

    /// Updates the clear color of the render pass descriptor.
    ///
    /// - Parameter color: The new clear color.
    public func setClearColor(_ color: MTLClearColor) {
        renderPassDescriptor.colorAttachments[0].clearColor = color
    }

    /// Creates a new texture manager with different dimensions, preserving the sample count.
    ///
    /// Since `TextureManager` is immutable, resizing returns a new instance.
    ///
    /// - Parameters:
    ///   - width: The new width in pixels.
    ///   - height: The new height in pixels.
    ///   - pixelFormat: The color texture pixel format.
    ///   - depthFormat: The depth texture pixel format.
    ///   - clearColor: The clear color.
    /// - Returns: A new `TextureManager` with the specified dimensions.
    public func resize(
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .depth32Float,
        clearColor: MTLClearColor = .black
    ) throws -> TextureManager {
        try TextureManager(
            device: device,
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            depthFormat: depthFormat,
            clearColor: clearColor,
            sampleCount: sampleCount
        )
    }
}

// MARK: - MTLClearColor Extension

extension MTLClearColor {
    /// Opaque black clear color.
    public static let black = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    /// Opaque white clear color.
    public static let white = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
    /// Transparent clear color.
    public static let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
}
