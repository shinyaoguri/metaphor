import Metal
import MetalKit
import AppKit

/// 画像を表すクラス。MTLTextureをラップする。
@MainActor
public final class MImage {
    /// Metal テクスチャ
    public let texture: MTLTexture

    /// 画像の幅（ピクセル）
    public let width: Float

    /// 画像の高さ（ピクセル）
    public let height: Float

    /// ファイルパスから読み込み
    public init(path: String, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        let url = URL(fileURLWithPath: path)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false
        ]
        self.texture = try loader.newTexture(URL: url, options: options)
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    /// バンドルリソースから読み込み
    public init(named name: String, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false
        ]
        self.texture = try loader.newTexture(name: name, scaleFactor: 1.0, bundle: nil, options: options)
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    /// NSImageから生成
    public init(nsImage: NSImage, device: MTLDevice) throws {
        let loader = MTKTextureLoader(device: device)
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MImageError.invalidImage
        }
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false
        ]
        self.texture = try loader.newTexture(cgImage: cgImage, options: options)
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }

    /// 既存のMTLTextureから生成
    public init(texture: MTLTexture) {
        self.texture = texture
        self.width = Float(texture.width)
        self.height = Float(texture.height)
    }
}

public enum MImageError: Error {
    case invalidImage
}
