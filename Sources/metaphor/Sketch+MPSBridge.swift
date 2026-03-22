import MetaphorCore
import MetaphorMPS

// MARK: - MPS ブリッジ

extension Sketch {
    /// MPS（Metal Performance Shaders）画像フィルタを作成します。
    ///
    /// - Returns: 新しい ``MetaphorMPS/MPSImageFilterWrapper`` インスタンス。
    public func createMPSFilter() -> MPSImageFilterWrapper {
        MPSImageFilterWrapper(device: context.renderer.device, commandQueue: context.renderer.commandQueue)
    }

    /// GPU アクセラレーションによるレイ交差クエリ用のレイトレーサーを作成します。
    ///
    /// Metal ネイティブ Ray Tracing API を使用してインライン交差判定を行います。
    /// - Parameters:
    ///   - width: 出力画像の幅（ピクセル単位）。
    ///   - height: 出力画像の高さ（ピクセル単位）。
    /// - Returns: 新しい ``MetaphorMPS/MPSRayTracer`` インスタンス。
    public func createRayTracer(width: Int, height: Int) throws -> MPSRayTracer {
        try MPSRayTracer(device: context.renderer.device, commandQueue: context.renderer.commandQueue, width: width, height: height)
    }
}
