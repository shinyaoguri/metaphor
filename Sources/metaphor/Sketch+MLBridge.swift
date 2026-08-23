import MetaphorCore
import MetaphorML

// MARK: - MLTextureConverter ブリッジ

extension Sketch {
    /// Creates a texture converter for Metal-CoreML interoperation.
    ///
    /// Use it to convert between MTLTexture, CVPixelBuffer and CGImage when working
    /// directly with the CoreML or Vision frameworks.
    ///
    /// - Returns: A new ``MetaphorML/MLTextureConverter`` instance.
    public func createMLTextureConverter() -> MLTextureConverter {
        MLTextureConverter(
            device: context.renderer.device, commandQueue: context.renderer.commandQueue)
    }
}
