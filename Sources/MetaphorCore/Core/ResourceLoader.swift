@preconcurrency import Metal
@preconcurrency import MetalKit
import AppKit

/// メインスレッドをブロックせずにリソースを非同期で読み込みます。
///
/// ``ResourceLoader`` は `MTKTextureLoader` の非同期メソッドをラップし、
/// 画像やモデルをメインスレッド外で読み込むための便利な API を提供します。
@MainActor
public final class ResourceLoader {
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader

    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }

    private nonisolated static var textureOptions: [MTKTextureLoader.Option: Any] {
        [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .SRGB: false,
        ]
    }

    // MARK: - 非同期画像読み込み

    /// ファイルパスから画像を非同期で読み込みます。
    ///
    /// ファイル I/O とテクスチャデコードは `MTKTextureLoader` の非同期 API により
    /// メインスレッド外で実行されます。
    ///
    /// - Parameter path: 画像の絶対ファイルパス
    /// - Returns: 読み込まれたテクスチャに基づく新しい ``MImage``
    public func loadImageAsync(path: String) async throws -> MImage {
        let url = URL(fileURLWithPath: path)
        let texture = try await textureLoader.newTexture(
            URL: url, options: Self.textureOptions
        )
        return MImage(texture: texture)
    }

    /// 名前付き画像リソースを非同期で読み込みます。
    ///
    /// - Parameter name: バンドル内の画像リソース名
    /// - Returns: 読み込まれたテクスチャに基づく新しい ``MImage``
    public func loadImageAsync(named name: String) async throws -> MImage {
        let texture = try await textureLoader.newTexture(
            name: name, scaleFactor: 1.0, bundle: nil, options: Self.textureOptions
        )
        return MImage(texture: texture)
    }

    /// `NSImage` から画像を非同期で読み込みます。
    ///
    /// - Parameter nsImage: 変換する `NSImage`
    /// - Returns: 読み込まれたテクスチャに基づく新しい ``MImage``
    public func loadImageAsync(nsImage: NSImage) async throws -> MImage {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MetaphorError.image(.invalidImage)
        }
        let texture = try await textureLoader.newTexture(
            cgImage: cgImage, options: Self.textureOptions
        )
        return MImage(texture: texture)
    }

    // MARK: - 非同期モデル読み込み

    /// 3D モデルを非同期で読み込みます。
    ///
    /// Model I/O は MainActor を必要としますが、async 関数でラップすることで
    /// 呼び出し側が `await` を使用して構造化並行処理と統合できます。
    ///
    /// - Parameters:
    ///   - path: モデルのファイルパス
    ///   - normalize: バウンディングボックスを正規化するかどうか
    /// - Returns: 読み込まれた ``Mesh``
    public func loadModelAsync(path: String, normalize: Bool = true) async throws -> Mesh {
        let url = URL(fileURLWithPath: path)
        return try ModelIOLoader.load(device: device, url: url, normalize: normalize)
    }
}
