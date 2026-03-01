import Metal
import MetalKit
import AppKit

/// 画像を表すクラス。MTLTextureをラップする。
@MainActor
public final class MImage {
    /// Metal テクスチャ
    public private(set) var texture: MTLTexture

    /// 画像の幅（ピクセル）
    public private(set) var width: Float

    /// 画像の高さ（ピクセル）
    public private(set) var height: Float

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

    // MARK: - Pixel Access

    /// ピクセルデータ（RGBA、loadPixels()後に有効）
    public var pixels: [UInt8] = []

    /// GPUテクスチャからCPUにピクセルデータを読み込む
    public func loadPixels() {
        let w = Int(width)
        let h = Int(height)
        let bytesPerRow = w * 4
        pixels = [UInt8](repeating: 0, count: bytesPerRow * h)

        if texture.storageMode == .private {
            // private storageの場合はBlitで一時テクスチャにコピーが必要
            // ここでは直接読み取りを試みるが、privateの場合は空になる可能性あり
            // 完全なサポートにはcommand bufferが必要
            return
        }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: w, height: h, depth: 1))
        texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        // BGRA → RGBA 変換
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = pixels[i]
            pixels[i] = pixels[i + 2]
            pixels[i + 2] = b
        }
    }

    /// CPUのピクセルデータをGPUテクスチャに書き戻す
    public func updatePixels() {
        let w = Int(width)
        let h = Int(height)
        let bytesPerRow = w * 4
        guard pixels.count == bytesPerRow * h else { return }

        // RGBA → BGRA 変換
        var bgra = pixels
        for i in stride(from: 0, to: bgra.count, by: 4) {
            let r = bgra[i]
            bgra[i] = bgra[i + 2]
            bgra[i + 2] = r
        }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: w, height: h, depth: 1))
        texture.replace(region: region, mipmapLevel: 0, withBytes: bgra, bytesPerRow: bytesPerRow)
    }

    /// 指定座標のピクセル色を返す（loadPixels()後に有効）
    public func get(_ x: Int, _ y: Int) -> Color {
        let w = Int(width)
        guard x >= 0, x < w, y >= 0, y < Int(height) else { return .black }
        guard !pixels.isEmpty else { return .black }
        let i = (y * w + x) * 4
        return Color(
            r: Float(pixels[i]) / 255.0,
            g: Float(pixels[i + 1]) / 255.0,
            b: Float(pixels[i + 2]) / 255.0,
            a: Float(pixels[i + 3]) / 255.0
        )
    }

    /// 指定座標にピクセル色を設定（updatePixels()で反映）
    public func set(_ x: Int, _ y: Int, _ color: Color) {
        let w = Int(width)
        guard x >= 0, x < w, y >= 0, y < Int(height) else { return }
        let bytesPerRow = w * 4
        if pixels.isEmpty {
            pixels = [UInt8](repeating: 0, count: bytesPerRow * Int(height))
        }
        let i = (y * w + x) * 4
        pixels[i] = UInt8(max(0, min(255, color.r * 255)))
        pixels[i + 1] = UInt8(max(0, min(255, color.g * 255)))
        pixels[i + 2] = UInt8(max(0, min(255, color.b * 255)))
        pixels[i + 3] = UInt8(max(0, min(255, color.a * 255)))
    }

    /// テクスチャを差し替える（GPU フィルタ適用後に使用）
    internal func replaceTexture(_ newTexture: MTLTexture) {
        self.texture = newTexture
        self.width = Float(newTexture.width)
        self.height = Float(newTexture.height)
        self.pixels = []
    }

    /// フィルタを適用（loadPixels→処理→updatePixels を一括実行）
    public func filter(_ type: FilterType) {
        ImageFilter.apply(type, to: self)
    }

    /// 空のMImageを作成（ピクセル操作用）
    public static func createImage(_ width: Int, _ height: Int, device: MTLDevice) -> MImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        let img = MImage(texture: texture)
        img.pixels = [UInt8](repeating: 0, count: width * height * 4)
        return img
    }
}

public enum MImageError: Error {
    case invalidImage
}
