import Metal

/// 2パスレンダリングシステム用のオフスクリーンレンダーターゲットテクスチャを管理します。
///
/// `TextureManager` はオフスクリーンレンダリングに使用するカラー、デプス、
/// およびオプションの MSAA テクスチャを作成・保持します。イミュータブル設計に従い、
/// リサイズは既存インスタンスの変更ではなく新しいインスタンスの作成で行います。
///
/// ```swift
/// let textures = try TextureManager(device: device, width: 1920, height: 1080)
/// ```
public final class TextureManager {
    /// テクスチャ作成に使用される Metal デバイス
    public let device: MTLDevice

    /// 解決済みカラーテクスチャ（MSAA 無効時のレンダーターゲット）
    public private(set) var colorTexture: MTLTexture

    /// MSAA マルチサンプルカラーテクスチャ（MSAA 有効時のみ存在）
    private var msaaColorTexture: MTLTexture?

    /// MSAA マルチサンプルデプステクスチャ（MSAA 有効時のみ存在）
    private var msaaDepthTexture: MTLTexture?

    /// デプステスト用デプステクスチャ
    public private(set) var depthTexture: MTLTexture

    /// 管理テクスチャ用に構成されたレンダーパスデスクリプタ
    public private(set) var renderPassDescriptor: MTLRenderPassDescriptor

    /// 管理テクスチャの幅（ピクセル）
    public let width: Int

    /// 管理テクスチャの高さ（ピクセル）
    public let height: Int

    /// MSAA サンプル数 (1 = 無効, 4 = 4x MSAA)
    public let sampleCount: Int

    /// 管理テクスチャのアスペクト比 (幅 / 高さ)
    public var aspectRatio: Float {
        Float(width) / Float(height)
    }

    /// 指定されたサイズで新しいテクスチャマネージャーを作成します。
    ///
    /// - Parameters:
    ///   - device: テクスチャ作成に使用する Metal デバイス
    ///   - width: テクスチャの幅（ピクセル）
    ///   - height: テクスチャの高さ（ピクセル）
    ///   - pixelFormat: カラーテクスチャのピクセルフォーマット
    ///   - depthFormat: デプステクスチャのピクセルフォーマット
    ///   - clearColor: レンダーパスのクリアカラー
    ///   - sampleCount: MSAA サンプル数。デバイスが非対応の場合は 1 にフォールバック
    /// - Throws: テクスチャを作成できなかった場合 ``MetaphorError/textureCreationFailed(width:height:format:)``
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

        // サンプル数の検証: デバイスがサポートしていない場合は 1 にフォールバック
        if sampleCount > 1 && !device.supportsTextureSampleCount(sampleCount) {
            metaphorWarning("sampleCount \(sampleCount) is not supported by this device. Falling back to 1.")
            self.sampleCount = 1
        } else {
            self.sampleCount = sampleCount
        }

        // カラーテクスチャ（リゾルブターゲット / MSAA 無効時のレンダーターゲット）
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
            throw MetaphorError.textureCreationFailed(width: width, height: height, format: "depth")
        }
        self.depthTexture = depthTex

        // MSAA テクスチャ
        if self.sampleCount > 1 {
            let msaaColorDesc = MTLTextureDescriptor()
            msaaColorDesc.textureType = .type2DMultisample
            msaaColorDesc.pixelFormat = pixelFormat
            msaaColorDesc.width = width
            msaaColorDesc.height = height
            msaaColorDesc.sampleCount = self.sampleCount
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

        // レンダーパスデスクリプタ
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].clearColor = clearColor
        rpd.colorAttachments[0].loadAction = .clear
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1.0

        if self.sampleCount > 1 {
            // MSAA: マルチサンプルテクスチャにレンダリングし、colorTexture にリゾルブ
            rpd.colorAttachments[0].texture = msaaColorTexture
            rpd.colorAttachments[0].resolveTexture = colorTexture
            rpd.colorAttachments[0].storeAction = .storeAndMultisampleResolve
            rpd.depthAttachment.texture = msaaDepthTexture
        } else {
            // MSAA なし: colorTexture に直接レンダリング
            rpd.colorAttachments[0].texture = colorTexture
            rpd.colorAttachments[0].storeAction = .store
            rpd.depthAttachment.texture = depthTexture
        }
        self.renderPassDescriptor = rpd
    }

    /// Full HD (1920x1080) のテクスチャマネージャーを作成します。
    ///
    /// - Parameters:
    ///   - device: Metal デバイス
    ///   - clearColor: クリアカラー
    ///   - sampleCount: MSAA サンプル数
    /// - Returns: 1920x1080 で構成された新しい `TextureManager`
    public static func fullHD(device: MTLDevice, clearColor: MTLClearColor = .black, sampleCount: Int = 4) throws -> TextureManager {
        try TextureManager(device: device, width: 1920, height: 1080, clearColor: clearColor, sampleCount: sampleCount)
    }

    /// 4K UHD (3840x2160) のテクスチャマネージャーを作成します。
    ///
    /// - Parameters:
    ///   - device: Metal デバイス
    ///   - clearColor: クリアカラー
    ///   - sampleCount: MSAA サンプル数
    /// - Returns: 3840x2160 で構成された新しい `TextureManager`
    public static func uhd4K(device: MTLDevice, clearColor: MTLClearColor = .black, sampleCount: Int = 4) throws -> TextureManager {
        try TextureManager(device: device, width: 3840, height: 2160, clearColor: clearColor, sampleCount: sampleCount)
    }

    /// 指定サイズの正方形テクスチャマネージャーを作成します。
    ///
    /// - Parameters:
    ///   - device: Metal デバイス
    ///   - size: 幅と高さ（ピクセル）
    ///   - clearColor: クリアカラー
    ///   - sampleCount: MSAA サンプル数
    /// - Returns: 幅と高さが等しい新しい `TextureManager`
    public static func square(device: MTLDevice, size: Int, clearColor: MTLClearColor = .black, sampleCount: Int = 4) throws -> TextureManager {
        try TextureManager(device: device, width: size, height: size, clearColor: clearColor, sampleCount: sampleCount)
    }

    /// レンダーパスデスクリプタのクリアカラーを更新します。
    ///
    /// - Parameter color: 新しいクリアカラー
    public func setClearColor(_ color: MTLClearColor) {
        renderPassDescriptor.colorAttachments[0].clearColor = color
    }

    /// 次のレンダーパスで前フレームをクリアするか保持するかを設定します。
    ///
    /// - Parameter shouldClear: true の場合は `.clear` ロードアクション、false の場合は `.load`
    public func setShouldClear(_ shouldClear: Bool) {
        renderPassDescriptor.colorAttachments[0].loadAction = shouldClear ? .clear : .load
        // デプスは各フレームで正しい Z テスト用に常にクリア

        // MSAA ではマルチサンプルテクスチャの内容を保持するため常に
        // .storeAndMultisampleResolve を使用します。これにより、クリアから保持への
        // 遷移が予期せず発生しても、.load が有効なデータを読み取れることを保証します
        // （ストアアクションは次のフレームが background() を呼ぶかどうか判明する前にコミットされます）。
        // Apple Silicon での追加帯域幅コストは無視できます。
        if sampleCount > 1 {
            renderPassDescriptor.colorAttachments[0].storeAction = .storeAndMultisampleResolve
        }
    }

    /// サンプル数を保持したまま異なるサイズの新しいテクスチャマネージャーを作成します。
    ///
    /// `TextureManager` はイミュータブルなため、リサイズは新しいインスタンスを返します。
    ///
    /// - Parameters:
    ///   - width: 新しい幅（ピクセル）
    ///   - height: 新しい高さ（ピクセル）
    ///   - pixelFormat: カラーテクスチャのピクセルフォーマット
    ///   - depthFormat: デプステクスチャのピクセルフォーマット
    ///   - clearColor: クリアカラー
    /// - Returns: 指定されたサイズの新しい `TextureManager`
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

// MARK: - MTLClearColor 拡張

extension MTLClearColor {
    /// 不透明黒のクリアカラー
    public static let black = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    /// 不透明白のクリアカラー
    public static let white = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
    /// 透明のクリアカラー
    public static let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
}
