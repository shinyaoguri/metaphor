import simd

/// Defines the available GameplayKit noise algorithms.
public enum NoiseType: Sendable {
    /// Perlin noise (based on GKPerlinNoiseSource).
    case perlin
    /// Voronoi / Worley noise (cellular pattern, organic texture).
    case voronoi
    /// Billow noise (soft, cloud-like pattern).
    case billow
    /// Ridged multifractal noise (mountainous terrain, lightning pattern).
    case ridged
    /// Concentric cylinder pattern.
    case cylinders
    /// Concentric sphere pattern.
    case spheres
    /// Checkerboard pattern.
    case checkerboard
    /// Constant-value noise.
    case constant(value: Double)
}

/// Configures the parameters for GKNoise generation.
public struct NoiseConfig: Sendable {
    /// Number of fractal octaves (default is 6).
    public var octaves: Int

    /// Base frequency (default is 1.0).
    public var frequency: Double

    /// Lacunarity (frequency multiplier between octaves, default is 2.0).
    public var lacunarity: Double

    /// Seed value for the noise generator.
    public var seed: Int32

    /// Amplitude decay rate per octave (persistence, default is 0.5).
    public var persistence: Double

    /// Whether output normalization is enabled (remaps to 0.0-1.0).
    public var normalized: Bool

    /// Voronoi-specific: use distance as the noise value.
    public var voronoiDistanceEnabled: Bool

    /// Sampling scale (maps to noiseMap's sampleSize).
    public var sampleScale: SIMD2<Double>

    /// Sampling offset.
    public var origin: SIMD2<Double>

    /// Creates a noise configuration with the given parameters.
    /// - Parameters:
    ///   - octaves: Number of fractal octaves (default is 6).
    ///   - frequency: Base frequency (default is 1.0).
    ///   - lacunarity: Frequency multiplier between octaves (default is 2.0).
    ///   - seed: Seed value (default is 0).
    ///   - persistence: Amplitude decay rate (default is 0.5).
    ///   - normalized: Remaps output to 0.0-1.0 (default is true).
    ///   - voronoiDistanceEnabled: Use distance as the Voronoi value (default is true).
    ///   - sampleScale: Sampling scale (default is (1.0, 1.0)).
    ///   - origin: Sampling offset (default is zero).
    public init(
        octaves: Int = 6,
        frequency: Double = 1.0,
        lacunarity: Double = 2.0,
        seed: Int32 = 0,
        persistence: Double = 0.5,
        normalized: Bool = true,
        voronoiDistanceEnabled: Bool = true,
        sampleScale: SIMD2<Double> = SIMD2(1.0, 1.0),
        origin: SIMD2<Double> = .zero
    ) {
        self.octaves = octaves
        self.frequency = frequency
        self.lacunarity = lacunarity
        self.seed = seed
        self.persistence = persistence
        self.normalized = normalized
        self.voronoiDistanceEnabled = voronoiDistanceEnabled
        self.sampleScale = sampleScale
        self.origin = origin
    }
}
