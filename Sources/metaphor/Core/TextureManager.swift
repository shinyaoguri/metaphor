import Metal

/// オフスクリーンレンダリング用のテクスチャを管理するクラス
public final class TextureManager {
    public let device: MTLDevice

    /// カラーテクスチャ（リゾルブ先 / MSAA無効時はレンダーターゲット）
    public private(set) var colorTexture: MTLTexture

    /// MSAAカラーテクスチャ（MSAA有効時のみ）
    private var msaaColorTexture: MTLTexture?

    /// MSAAデプステクスチャ（MSAA有効時のみ）
    private var msaaDepthTexture: MTLTexture?

    /// デプステクスチャ
    public private(set) var depthTexture: MTLTexture

    /// レンダーパスディスクリプタ
    public private(set) var renderPassDescriptor: MTLRenderPassDescriptor

    /// テクスチャの幅
    public let width: Int

    /// テクスチャの高さ
    public let height: Int

    /// MSAAサンプル数（1 = 無効、4 = 4x MSAA）
    public let sampleCount: Int

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
    ///   - sampleCount: MSAAサンプル数（デフォルト: 4）
    public init(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .depth32Float,
        clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1),
        sampleCount: Int = 4
    ) {
        self.device = device
        self.width = width
        self.height = height
        self.sampleCount = sampleCount

        // カラーテクスチャ（リゾルブ先 / MSAA無効時はレンダーターゲット）
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        guard let colorTex = device.makeTexture(descriptor: colorDescriptor) else {
            fatalError("[TextureManager] Failed to create color texture (\(width)x\(height))")
        }
        self.colorTexture = colorTex

        // デプステクスチャ
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        guard let depthTex = device.makeTexture(descriptor: depthDescriptor) else {
            fatalError("[TextureManager] Failed to create depth texture (\(width)x\(height))")
        }
        self.depthTexture = depthTex

        // MSAA テクスチャ
        if sampleCount > 1 {
            let msaaColorDesc = MTLTextureDescriptor()
            msaaColorDesc.textureType = .type2DMultisample
            msaaColorDesc.pixelFormat = pixelFormat
            msaaColorDesc.width = width
            msaaColorDesc.height = height
            msaaColorDesc.sampleCount = sampleCount
            msaaColorDesc.usage = .renderTarget
            msaaColorDesc.storageMode = .private
            msaaColorTexture = device.makeTexture(descriptor: msaaColorDesc)

            let msaaDepthDesc = MTLTextureDescriptor()
            msaaDepthDesc.textureType = .type2DMultisample
            msaaDepthDesc.pixelFormat = depthFormat
            msaaDepthDesc.width = width
            msaaDepthDesc.height = height
            msaaDepthDesc.sampleCount = sampleCount
            msaaDepthDesc.usage = .renderTarget
            msaaDepthDesc.storageMode = .private
            msaaDepthTexture = device.makeTexture(descriptor: msaaDepthDesc)
        }

        // レンダーパスディスクリプタ
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].clearColor = clearColor
        rpd.colorAttachments[0].loadAction = .clear
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1.0

        if sampleCount > 1 {
            // MSAA: マルチサンプルテクスチャに描画し、colorTextureにリゾルブ
            rpd.colorAttachments[0].texture = msaaColorTexture
            rpd.colorAttachments[0].resolveTexture = colorTexture
            rpd.colorAttachments[0].storeAction = .multisampleResolve
            rpd.depthAttachment.texture = msaaDepthTexture
        } else {
            // MSAA無効: 従来通り
            rpd.colorAttachments[0].texture = colorTexture
            rpd.colorAttachments[0].storeAction = .store
            rpd.depthAttachment.texture = depthTexture
        }
        self.renderPassDescriptor = rpd
    }

    /// Full HD (1920x1080) プリセット
    public static func fullHD(device: MTLDevice, clearColor: MTLClearColor = .black, sampleCount: Int = 4) -> TextureManager {
        TextureManager(device: device, width: 1920, height: 1080, clearColor: clearColor, sampleCount: sampleCount)
    }

    /// 4K (3840x2160) プリセット
    public static func uhd4K(device: MTLDevice, clearColor: MTLClearColor = .black, sampleCount: Int = 4) -> TextureManager {
        TextureManager(device: device, width: 3840, height: 2160, clearColor: clearColor, sampleCount: sampleCount)
    }

    /// 正方形テクスチャ
    public static func square(device: MTLDevice, size: Int, clearColor: MTLClearColor = .black, sampleCount: Int = 4) -> TextureManager {
        TextureManager(device: device, width: size, height: size, clearColor: clearColor, sampleCount: sampleCount)
    }

    /// クリアカラーを動的に変更
    public func setClearColor(_ color: MTLClearColor) {
        renderPassDescriptor.colorAttachments[0].clearColor = color
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
            clearColor: clearColor,
            sampleCount: sampleCount
        )
    }
}

// MARK: - MTLClearColor Extension

extension MTLClearColor {
    public static let black = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let white = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
    public static let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
}
