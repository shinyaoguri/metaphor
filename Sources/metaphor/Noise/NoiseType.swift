import simd

/// Define the available GameplayKit noise algorithms.
public enum NoiseType: Sendable {
    /// Perlin noise (based on GKPerlinNoiseSource).
    case perlin
    /// Voronoi / Worley noise (cell patterns, organic textures).
    case voronoi
    /// Billow noise (soft, cloud-like patterns).
    case billow
    /// Ridged multifractal noise (mountain terrain, lightning patterns).
    case ridged
    /// Concentric cylinder pattern.
    case cylinders
    /// Concentric sphere pattern.
    case spheres
    /// Checkerboard pattern.
    case checkerboard
    /// Constant value noise.
    case constant(value: Double)
}

/// Configure parameters for GKNoise generation.
public struct NoiseConfig: Sendable {
    /// Number of fractal octaves (defaults to 6).
    public var octaves: Int

    /// Base frequency (defaults to 1.0).
    public var frequency: Double

    /// Lacunarity (frequency multiplier between octaves, defaults to 2.0).
    public var lacunarity: Double

    /// Seed value for the noise generator.
    public var seed: Int32

    /// Amplitude decay rate per octave (persistence, defaults to 0.5).
    public var persistence: Double

    /// Enable output normalization (remap to 0.0-1.0).
    public var normalized: Bool

    /// Voronoi-specific: use distance as the noise value.
    public var voronoiDistanceEnabled: Bool

    /// Sampling scale (maps to noiseMap's sampleSize).
    public var sampleScale: SIMD2<Double>

    /// Sampling offset.
    public var origin: SIMD2<Double>

    /// Create a noise configuration with the given parameters.
    /// - Parameters:
    ///   - octaves: Number of fractal octaves (defaults to 6).
    ///   - frequency: Base frequency (defaults to 1.0).
    ///   - lacunarity: Frequency multiplier between octaves (defaults to 2.0).
    ///   - seed: Seed value (defaults to 0).
    ///   - persistence: Amplitude decay rate (defaults to 0.5).
    ///   - normalized: Remap output to 0.0-1.0 (defaults to true).
    ///   - voronoiDistanceEnabled: Use distance as Voronoi value (defaults to true).
    ///   - sampleScale: Sampling scale (defaults to (1.0, 1.0)).
    ///   - origin: Sampling offset (defaults to zero).
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
