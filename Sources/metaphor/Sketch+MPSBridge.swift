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

    /// GPU アクセラレーションによるレイ交差クエリ用の MPS レイトレーサーを作成します。
    ///
    /// - Parameters:
    ///   - width: 出力画像の幅（ピクセル単位）。
    ///   - height: 出力画像の高さ（ピクセル単位）。
    /// - Returns: 新しい ``MetaphorMPS/MPSRayTracer`` インスタンス。
    @available(macOS, deprecated: 14.0, message: "Uses deprecated MPS ray tracing APIs; migrate to Metal ray tracing APIs")
    public func createRayTracer(width: Int, height: Int) throws -> MPSRayTracer {
        try MPSRayTracer(device: context.renderer.device, commandQueue: context.renderer.commandQueue, width: width, height: height)
    }
}
