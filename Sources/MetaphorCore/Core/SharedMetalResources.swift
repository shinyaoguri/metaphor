@preconcurrency import Metal

/// 複数のウィンドウやレンダラー間で共有可能な Metal リソースを保持します。
///
/// マルチウィンドウレンダリングでは、各 ``MetaphorRenderer`` が同じデバイス、
/// コマンドキュー、シェーダーライブラリ、デプスステンシルキャッシュを共有することで、
/// GPU 側の高コストなオブジェクトの重複を回避できます。
@MainActor
public final class SharedMetalResources {
    /// 全 GPU リソース作成に使用される Metal デバイス
    public let device: MTLDevice

    /// GPU へのワーク送信に使用されるコマンドキュー
    public let commandQueue: MTLCommandQueue

    /// コンパイル済み Metal シェーダー関数を含むシェーダーライブラリ
    public let shaderLibrary: ShaderLibrary

    /// レンダラー間で共有されるデプスステンシルステートキャッシュ
    public let depthStencilCache: DepthStencilCache

    /// 共有 Metal リソースを作成します。
    ///
    /// - Parameter device: 使用する Metal デバイス。`nil` の場合はシステムデフォルトを使用
    /// - Throws: デバイスまたはコマンドキューの作成に失敗した場合 ``MetaphorError``
    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else {
            throw MetaphorError.deviceNotAvailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetaphorError.commandQueueCreationFailed
        }
        self.device = device
        self.commandQueue = commandQueue
        self.shaderLibrary = try ShaderLibrary(device: device)
        self.depthStencilCache = DepthStencilCache(device: device)
    }
}
