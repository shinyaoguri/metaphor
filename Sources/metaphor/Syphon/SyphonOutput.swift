#if os(macOS)
import Metal
import Syphon
import Foundation

/// Syphon経由でテクスチャを他のアプリケーションに送信するためのラッパー
public final class SyphonOutput {
    private var server: SyphonMetalServer?
    private let device: MTLDevice

    /// Syphonサーバーの名前
    public var serverName: String? {
        server?.name
    }

    /// サーバーがアクティブかどうか
    public var isActive: Bool {
        server != nil
    }

    /// 初期化
    /// - Parameters:
    ///   - device: MTLDevice
    ///   - name: Syphonサーバー名（他のアプリから見える名前）
    public init(device: MTLDevice, name: String) {
        self.device = device
        self.server = SyphonMetalServer(name: name, device: device, options: nil)
    }

    /// テクスチャをSyphon経由で送信
    /// - Parameters:
    ///   - texture: 送信するテクスチャ
    ///   - commandBuffer: コマンドバッファ
    ///   - region: 送信する領域（nilの場合はテクスチャ全体）
    ///   - flipped: Y軸を反転するか
    public func publish(
        texture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        region: NSRect? = nil,
        flipped: Bool = false
    ) {
        guard let server = server else { return }

        let imageRegion = region ?? NSRect(
            x: 0,
            y: 0,
            width: texture.width,
            height: texture.height
        )

        server.publishFrameTexture(
            texture,
            on: commandBuffer,
            imageRegion: imageRegion,
            flipped: flipped
        )
    }

    /// サーバー名を変更
    /// - Parameter name: 新しいサーバー名
    public func rename(_ name: String) {
        server?.stop()
        server = SyphonMetalServer(name: name, device: device, options: nil)
    }

    /// サーバーを停止
    public func stop() {
        server?.stop()
        server = nil
    }

    deinit {
        stop()
    }
}
#endif
