import Metal

/// オフスクリーンレンダリング用のテクスチャを管理するクラス
public final class TextureManager {
    public let device: MTLDevice

    /// カラーテクスチャ
    public private(set) var colorTexture: MTLTexture!

    /// デプステクスチャ
    public private(set) var depthTexture: MTLTexture!

    /// レンダーパスディスクリプタ
    public private(set) var renderPassDescriptor: MTLRenderPassDescriptor!

    /// テクスチャの幅
    public let width: Int

    /// テクスチャの高さ
    public let height: Int

    /// アスペクト比
    public var aspectRatio: Float {
        Float(width) / Float(height)
    }

    /// 初期化
    /// - Parameters:
    ///   - device: MTLDevice
    ///   - width: テクスチャの幅
    ///   - height: テクスチャの高さ
    ///   - pixelFormat: ピクセルフォーマット（デフォルト: .bgra8Unorm）
    ///   - depthFormat: デプスフォーマット（デフォルト: .depth32Float）
    ///   - clearColor: クリアカラー
    public init(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .depth32Float,
        clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    ) {
        self.device = device
        self.width = width
        self.height = height

        createTextures(pixelFormat: pixelFormat, depthFormat: depthFormat, clearColor: clearColor)
    }

    /// Full HD (1920x1080) プリセット
    public static func fullHD(device: MTLDevice, clearColor: MTLClearColor = .black) -> TextureManager {
        TextureManager(device: device, width: 1920, height: 1080, clearColor: clearColor)
    }

    /// 4K (3840x2160) プリセット
    public static func uhd4K(device: MTLDevice, clearColor: MTLClearColor = .black) -> TextureManager {
        TextureManager(device: device, width: 3840, height: 2160, clearColor: clearColor)
    }

    /// 正方形テクスチャ
    public static func square(device: MTLDevice, size: Int, clearColor: MTLClearColor = .black) -> TextureManager {
        TextureManager(device: device, width: size, height: size, clearColor: clearColor)
    }

    private func createTextures(
        pixelFormat: MTLPixelFormat,
        depthFormat: MTLPixelFormat,
        clearColor: MTLClearColor
    ) {
        // カラーテクスチャ
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        colorTexture = device.makeTexture(descriptor: colorDescriptor)

        // デプステクスチャ
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        depthTexture = device.makeTexture(descriptor: depthDescriptor)

        // レンダーパスディスクリプタ
        renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = colorTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
    }

    /// テクスチャをリサイズ（再作成）
    public func resize(
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .depth32Float,
        clearColor: MTLClearColor = .black
    ) -> TextureManager {
        TextureManager(
            device: device,
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            depthFormat: depthFormat,
            clearColor: clearColor
        )
    }
}

// MARK: - MTLClearColor Extension

extension MTLClearColor {
    public static let black = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let white = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
    public static let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
}
