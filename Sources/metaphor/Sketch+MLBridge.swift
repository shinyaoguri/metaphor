import MetaphorCore
import MetaphorML

// MARK: - MLTextureConverter Bridge

extension Sketch {
    /// Create a texture converter for Metal-CoreML interoperability.
    ///
    /// Use this to convert between MTLTexture, CVPixelBuffer, and CGImage
    /// when working with CoreML or Vision frameworks directly.
    ///
    /// - Returns: A new ``MetaphorML/MLTextureConverter`` instance.
    public func createMLTextureConverter() -> MLTextureConverter {
        MLTextureConverter(device: context.renderer.device, commandQueue: context.renderer.commandQueue)
    }
}
