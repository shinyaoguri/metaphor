import MetaphorCore
import MetaphorNoise

// MARK: - GameplayKit ノイズブリッジ

extension Sketch {
    /// Creates a GameplayKit noise generator.
    ///
    /// - Parameters:
    ///   - type: The noise algorithm to use.
    ///   - config: The noise generation settings.
    /// - Returns: A new ``MetaphorNoise/GKNoiseWrapper`` instance.
    public func createNoise(_ type: NoiseType, config: NoiseConfig = NoiseConfig())
        -> GKNoiseWrapper
    {
        GKNoiseWrapper(type: type, config: config, device: context.renderer.device)
    }

    /// Generates a noise texture as an image (a convenience method).
    ///
    /// - Parameters:
    ///   - type: The noise algorithm to use.
    ///   - width: The texture width, in pixels.
    ///   - height: The texture height, in pixels.
    ///   - config: The noise generation settings.
    /// - Returns: The generated noise image, or `nil` if generation fails.
    public func noiseTexture(
        _ type: NoiseType, width: Int, height: Int, config: NoiseConfig = NoiseConfig()
    ) -> MImage? {
        let noise = GKNoiseWrapper(type: type, config: config, device: context.renderer.device)
        return noise.image(width: width, height: height)
    }
}
