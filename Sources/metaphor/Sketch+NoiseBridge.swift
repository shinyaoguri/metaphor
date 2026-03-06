import MetaphorCore
import MetaphorNoise

// MARK: - GameplayKit Noise Bridge

extension Sketch {
    /// Create a GameplayKit noise generator.
    ///
    /// - Parameters:
    ///   - type: The noise algorithm type.
    ///   - config: The noise generation configuration.
    /// - Returns: A new ``GKNoiseWrapper`` instance.
    public func createNoise(_ type: NoiseType, config: NoiseConfig = NoiseConfig()) -> GKNoiseWrapper {
        GKNoiseWrapper(type: type, config: config, device: context.renderer.device)
    }

    /// Generate a noise texture as an image (convenience method).
    ///
    /// - Parameters:
    ///   - type: The noise algorithm type.
    ///   - width: The texture width in pixels.
    ///   - height: The texture height in pixels.
    ///   - config: The noise generation configuration.
    /// - Returns: The generated noise image, or `nil` if generation fails.
    public func noiseTexture(_ type: NoiseType, width: Int, height: Int, config: NoiseConfig = NoiseConfig()) -> MImage? {
        let noise = GKNoiseWrapper(type: type, config: config, device: context.renderer.device)
        return noise.image(width: width, height: height)
    }
}
