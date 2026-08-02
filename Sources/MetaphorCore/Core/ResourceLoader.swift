// @preconcurrency: `MTLTexture` / `MTLDevice` を nonisolated な async ヘルパーとの間で受け渡す。
// Swift 5.10 でのみ出る警告（新しい SDK では診断されない）。
// Metal の型は Sendable 注釈を持たないが、上記のとおり使い方は安全（Issue #328）。
@preconcurrency import Metal
// @preconcurrency: `MTKTextureLoader` を nonisolated な async ラッパーへ渡す（ローダはスレッドセーフ）。
// MetalKit の型は Sendable 注釈を持たないが、これらのオブジェクト自体はスレッドセーフ
// で、metaphor 側でも直列化・排他済み（Issue #328）。
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

    // MARK: - MTKTextureLoader 呼び出し（nonisolated ラッパー）
    //
    // `[MTKTextureLoader.Option: Any]` は非 Sendable（値が `Any`）。@MainActor から
    // `newTexture` を直接 await すると、この辞書を隔離ドメインの外へ渡すことになり
    // 警告になる（Swift 5.10。新しい SDK では出ない）。ローダを引数で受ける
    // nonisolated な入口をはさみ、辞書の生成と受け渡しを丸ごと nonisolated 側へ
    // 閉じ込めることで、境界を跨ぐ値を無くす（Issue #328）。

    private nonisolated static func newTexture(
        loader: MTKTextureLoader, url: URL
    ) async throws -> MTLTexture {
        try await loader.newTexture(URL: url, options: textureOptions)
    }

    private nonisolated static func newTexture(
        loader: MTKTextureLoader, name: String
    ) async throws -> MTLTexture {
        try await loader.newTexture(
            name: name, scaleFactor: 1.0, bundle: nil, options: textureOptions)
    }

    private nonisolated static func newTexture(
        loader: MTKTextureLoader, cgImage: CGImage
    ) async throws -> MTLTexture {
        try await loader.newTexture(cgImage: cgImage, options: textureOptions)
    }

    // MARK: - 非同期画像読み込み

    /// ファイルパスから画像を非同期で読み込みます。
    ///
    /// ファイル I/O とテクスチャデコードは `MTKTextureLoader` の非同期 API により
    /// メインスレッド外で実行されます。
    ///
    /// - Parameter path: 画像の絶対ファイルパス
    /// - Returns: 読み込まれたテクスチャに基づく新しい ``MImage``
    /// - Throws: ``MetaphorError/image(_:)`` の ``MetaphorError/ImageFailure/loadFailed(source:detail:)``
    ///   読み込みに失敗した場合
    public func loadImageAsync(path: String) async throws -> MImage {
        let url = URL(fileURLWithPath: path)
        let texture: MTLTexture
        do {
            texture = try await Self.newTexture(loader: textureLoader, url: url)
        } catch {
            throw MetaphorError.image(
                .loadFailed(source: path, detail: error.localizedDescription))
        }
        return MImage(texture: texture)
    }

    /// 名前付き画像リソースを非同期で読み込みます。
    ///
    /// - Parameter name: バンドル内の画像リソース名
    /// - Returns: 読み込まれたテクスチャに基づく新しい ``MImage``
    /// - Throws: ``MetaphorError/image(_:)`` の ``MetaphorError/ImageFailure/loadFailed(source:detail:)``
    ///   読み込みに失敗した場合
    public func loadImageAsync(named name: String) async throws -> MImage {
        let texture: MTLTexture
        do {
            texture = try await Self.newTexture(loader: textureLoader, name: name)
        } catch {
            throw MetaphorError.image(
                .loadFailed(source: name, detail: error.localizedDescription))
        }
        return MImage(texture: texture)
    }

    /// `NSImage` から画像を非同期で読み込みます。
    ///
    /// - Parameter nsImage: 変換する `NSImage`
    /// - Returns: 読み込まれたテクスチャに基づく新しい ``MImage``
    /// - Throws: ``MetaphorError/image(_:)``。`CGImage` へ変換できない場合は
    ///   ``MetaphorError/ImageFailure/invalidImage``、テクスチャ化に失敗した場合は
    ///   ``MetaphorError/ImageFailure/loadFailed(source:detail:)``
    public func loadImageAsync(nsImage: NSImage) async throws -> MImage {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MetaphorError.image(.invalidImage)
        }
        let texture: MTLTexture
        do {
            texture = try await Self.newTexture(loader: textureLoader, cgImage: cgImage)
        } catch {
            throw MetaphorError.image(
                .loadFailed(source: "NSImage", detail: error.localizedDescription))
        }
        return MImage(texture: texture)
    }

    // MARK: - 非同期モデル読み込み

    /// 3D モデルを非同期で読み込みます。
    ///
    /// Model I/O によるファイル解析はバックグラウンドタスクで実行し、
    /// Metal バッファを持つ ``Mesh`` の生成だけ MainActor に戻します。
    ///
    /// - Parameters:
    ///   - path: モデルのファイルパス
    ///   - normalize: バウンディングボックスを正規化するかどうか
    /// - Returns: 読み込まれた ``Mesh``
    /// - Throws: モデルを解析できない場合（メッシュ・頂点位置が無い、空メッシュなど）は
    ///   ``MetaphorError/mesh(_:)`` の ``MetaphorError/MeshFailure/parseError(_:)``、
    ///   GPU バッファを確保できない場合は ``MetaphorError/bufferCreationFailed(size:)``
    public func loadModelAsync(path: String, normalize: Bool = true) async throws -> Mesh {
        let url = URL(fileURLWithPath: path)
        return try await ModelIOLoader.loadAsync(device: device, url: url, normalize: normalize)
    }
}
