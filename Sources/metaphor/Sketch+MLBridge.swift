import MetaphorCore
import MetaphorML

// MARK: - MLTextureConverter ブリッジ

extension Sketch {
    /// Metal-CoreML 相互運用のためのテクスチャコンバーターを作成します。
    ///
    /// CoreML や Vision フレームワークを直接使用する際に、
    /// MTLTexture、CVPixelBuffer、CGImage 間の変換に使用します。
    ///
    /// - Returns: 新しい ``MetaphorML/MLTextureConverter`` インスタンス。
    public func createMLTextureConverter() -> MLTextureConverter {
        MLTextureConverter(device: context.renderer.device, commandQueue: context.renderer.commandQueue)
    }
}
