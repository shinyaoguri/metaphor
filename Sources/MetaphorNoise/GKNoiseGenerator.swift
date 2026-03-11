import GameplayKit
import Metal
import MetaphorCore
import simd

/// Wrap the GameplayKit noise system for procedural noise generation.
///
/// Support multiple noise algorithms (Voronoi, Billow, Ridged, etc.) and
/// provide both point sampling and texture generation.
///
/// ```swift
/// let noise = createNoise(.voronoi)
/// let value = noise.sample(x: 0.5, y: 0.3)
/// let tex = noise.texture(width: 512, height: 512)
/// ```
@MainActor
public final class GKNoiseWrapper {
    /// Return the noise type.
    public let type: NoiseType

    /// Access or modify the noise configuration.
    public var config: NoiseConfig {
        didSet { invalidateCache() }
    }

    private var gkNoise: GKNoise
    private var cachedMap: GKNoiseMap?
    private var cachedMapSize: (Int, Int) = (0, 0)
    private let device: MTLDevice

    // MARK: - Initialization

    public init(type: NoiseType, config: NoiseConfig = NoiseConfig(), device: MTLDevice) {
        self.type = type
        self.config = config
        self.device = device
        self.gkNoise = Self.makeGKNoise(type: type, config: config)
    }

    // MARK: - Point Sampling

    /// Sample the noise value at a 2D point.
    ///
    /// When `config.normalized` is true, the returned value is in the 0.0-1.0 range;
    /// otherwise, the raw range of -1.0 to 1.0 is returned.
    /// - Parameters:
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    /// - Returns: Noise value at the given point.
    public func sample(x: Float, y: Float) -> Float {
        let raw = gkNoise.value(atPosition: vector_float2(x, y))
        return config.normalized ? (raw + 1.0) * 0.5 : raw
    }

    /// Sample the noise value at a 2D point (Double precision input).
    /// - Parameters:
    ///   - x: X coordinate.
    ///   - y: Y coordinate.
    /// - Returns: Noise value at the given point.
    public func sample(x: Double, y: Double) -> Float {
        sample(x: Float(x), y: Float(y))
    }

    // MARK: - Grid Sampling

    /// Generate noise values as a 2D grid.
    /// - Parameters:
    ///   - width: Grid width in samples.
    ///   - height: Grid height in samples.
    /// - Returns: Flat array of noise values in row-major order.
    public func sampleGrid(width: Int, height: Int) -> [Float] {
        let map = makeNoiseMap(width: width, height: height)
        var result = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var val = map.value(at: vector_int2(Int32(x), Int32(y)))
                if config.normalized { val = (val + 1.0) * 0.5 }
                result[y * width + x] = val
            }
        }
        return result
    }

    // MARK: - Texture Generation

    /// Generate a grayscale BGRA8 noise texture.
    /// - Parameters:
    ///   - width: Texture width in pixels.
    ///   - height: Texture height in pixels.
    /// - Returns: Metal texture containing the noise, or nil on failure.
    public func texture(width: Int, height: Int) -> MTLTexture? {
        let values = sampleGrid(width: width, height: height)
        return NoiseTextureBuilder.buildTexture(
            device: device, values: values, width: width, height: height
        )
    }

    /// Generate a noise image.
    /// - Parameters:
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    /// - Returns: Image generated from the noise, or nil on failure.
    public func image(width: Int, height: Int) -> MImage? {
        guard let tex = texture(width: width, height: height) else { return nil }
        return MImage(texture: tex)
    }

    /// Generate a color-mapped noise texture using gradient stops.
    /// - Parameters:
    ///   - width: Texture width in pixels.
    ///   - height: Texture height in pixels.
    ///   - colorStops: Array of (position, BGRA color) pairs defining the gradient.
    /// - Returns: Metal texture with the color-mapped noise, or nil on failure.
    public func colorMappedTexture(
        width: Int, height: Int,
        colorStops: [(Float, SIMD4<UInt8>)]
    ) -> MTLTexture? {
        let values = sampleGrid(width: width, height: height)
        return NoiseTextureBuilder.buildColorMappedTexture(
            device: device, values: values, width: width, height: height,
            colorStops: colorStops
        )
    }

    // MARK: - Composable Operations

    /// Compose noise by adding another noise source.
    /// - Parameter other: Noise wrapper to add.
    public func add(_ other: GKNoiseWrapper) {
        gkNoise.add(other.gkNoise)
        invalidateCache()
    }

    /// Compose noise by multiplying with another noise source.
    /// - Parameter other: Noise wrapper to multiply.
    public func multiply(_ other: GKNoiseWrapper) {
        gkNoise.multiply(other.gkNoise)
        invalidateCache()
    }

    /// Invert the output values.
    public func invert() {
        gkNoise.invert()
        invalidateCache()
    }

    /// Apply absolute value to the output.
    public func applyAbsoluteValue() {
        gkNoise.applyAbsoluteValue()
        invalidateCache()
    }

    /// Apply turbulence distortion to the noise.
    /// - Parameters:
    ///   - frequency: Turbulence frequency.
    ///   - power: Turbulence power.
    ///   - roughness: Number of turbulence octaves.
    ///   - seed: Seed value for the turbulence.
    public func applyTurbulence(frequency: Double, power: Double, roughness: Int, seed: Int32) {
        gkNoise.applyTurbulence(
            frequency: frequency,
            power: power,
            roughness: Int32(roughness),
            seed: seed
        )
        invalidateCache()
    }

    /// Clamp the output values to a range.
    /// - Parameters:
    ///   - min: Lower bound.
    ///   - max: Upper bound.
    public func clamp(min: Double, max: Double) {
        gkNoise.clamp(lowerBound: min, upperBound: max)
        invalidateCache()
    }

    /// Raise the output values to a power.
    /// - Parameter exponent: The exponent to apply.
    public func raiseToPower(_ exponent: Double) {
        gkNoise.raiseToPower(exponent)
        invalidateCache()
    }

    // MARK: - Private

    private func invalidateCache() {
        cachedMap = nil
    }

    private func makeNoiseMap(width: Int, height: Int) -> GKNoiseMap {
        if let cached = cachedMap, cachedMapSize == (width, height) {
            return cached
        }

        let sx = config.sampleScale.x * Double(width)
        let sy = config.sampleScale.y * Double(height)
        let map = GKNoiseMap(
            gkNoise,
            size: vector_double2(sx, sy),
            origin: vector_double2(config.origin.x, config.origin.y),
            sampleCount: vector_int2(Int32(width), Int32(height)),
            seamless: false
        )
        cachedMap = map
        cachedMapSize = (width, height)
        return map
    }

    private static func makeGKNoise(type: NoiseType, config: NoiseConfig) -> GKNoise {
        let source: GKNoiseSource
        switch type {
        case .perlin:
            source = GKPerlinNoiseSource(
                frequency: config.frequency,
                octaveCount: config.octaves,
                persistence: config.persistence,
                lacunarity: config.lacunarity,
                seed: config.seed
            )
        case .voronoi:
            source = GKVoronoiNoiseSource(
                frequency: config.frequency,
                displacement: 1.0,
                distanceEnabled: config.voronoiDistanceEnabled,
                seed: config.seed
            )
        case .billow:
            source = GKBillowNoiseSource(
                frequency: config.frequency,
                octaveCount: config.octaves,
                persistence: config.persistence,
                lacunarity: config.lacunarity,
                seed: config.seed
            )
        case .ridged:
            source = GKRidgedNoiseSource(
                frequency: config.frequency,
                octaveCount: config.octaves,
                lacunarity: config.lacunarity,
                seed: config.seed
            )
        case .cylinders:
            source = GKCylindersNoiseSource(frequency: config.frequency)
        case .spheres:
            source = GKSpheresNoiseSource(frequency: config.frequency)
        case .checkerboard:
            source = GKCheckerboardNoiseSource(squareSize: config.frequency)
        case .constant(let value):
            source = GKConstantNoiseSource(value: value)
        }
        return GKNoise(source)
    }
}
