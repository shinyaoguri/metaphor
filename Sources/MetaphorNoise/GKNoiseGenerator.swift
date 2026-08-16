import GameplayKit
import Metal
import MetaphorCore
import simd

/// Wraps the GameplayKit noise system to provide procedural noise generation.
///
/// Supports multiple noise algorithms (Voronoi, Billow, Ridged, and others),
/// providing both point sampling and texture generation.
///
/// ```swift
/// let noise = createNoise(.voronoi)
/// let value = noise.sample(x: 0.5, y: 0.3)
/// let tex = noise.texture(width: 512, height: 512)
/// ```
///
/// ## Two entry points, two coordinate spaces
///
/// The noise can be read either point by point or as a grid, and **the two read the
/// field through different coordinate spaces**:
///
/// - ``sample(x:y:)`` samples the noise space directly. It applies neither
///   ``NoiseConfig/origin`` nor ``NoiseConfig/sampleScale``.
/// - ``sampleGrid(width:height:)`` — and therefore ``texture(width:height:)``,
///   ``image(width:height:)`` and ``colorMappedTexture(width:height:colorStops:)`` —
///   hands `origin` and `sampleScale` to `GKNoiseMap` and lets GameplayKit walk the grid.
///
/// Only the grid's first sample coincides with point sampling, at
/// `sample(x: origin.x, y: origin.y)`. Past that the two diverge, and they cannot be
/// lined up from here: GameplayKit does not step `GKNoiseMap` by
/// `origin + index × sampleScale`, and its effective step changes with the grid
/// dimensions rather than with `sampleScale` alone. Pick one entry point per sketch
/// instead of mixing them.
@MainActor
public final class GKNoiseWrapper {
    /// Returns the noise type.
    public let type: NoiseType

    /// Accesses or modifies the noise configuration.
    ///
    /// Source parameters such as frequency, octaves, and seed are baked in when
    /// the GKNoise is constructed, so changing them rebuilds the noise source.
    ///
    /// - Note: Compositions and transforms such as ``add(_:)``, ``multiply(_:)``,
    ///   and ``invert()`` are lost when the source is rebuilt. Reapply them after changing config if still needed.
    public var config: NoiseConfig {
        didSet {
            // ソースを再構築しないと frequency/octaves/seed 等の変更が
            // sample()/sampleGrid() に反映されない（origin/sampleScale/
            // normalized だけが効く silent failure になっていた）
            gkNoise = Self.makeGKNoise(type: type, config: config)
            invalidateCache()
        }
    }

    private var gkNoise: GKNoise
    private var cachedMap: GKNoiseMap?
    private var cachedMapSize: (Int, Int) = (0, 0)
    private let device: MTLDevice

    // MARK: - 初期化

    public init(type: NoiseType, config: NoiseConfig = NoiseConfig(), device: MTLDevice) {
        self.type = type
        self.config = config
        self.device = device
        self.gkNoise = Self.makeGKNoise(type: type, config: config)
    }

    // MARK: - ポイントサンプリング

    /// Samples the noise value at a 2D point.
    ///
    /// This samples the noise space directly: `x` and `y` reach the underlying noise
    /// source unchanged, so neither ``NoiseConfig/origin`` nor
    /// ``NoiseConfig/sampleScale`` is applied. Those two settings only steer the
    /// grid-based entry points. Offset and scale the coordinates yourself if you want
    /// them here.
    ///
    /// When `config.normalized` is true, the returned value is in the 0.0-1.0 range.
    /// Otherwise, the raw -1.0-1.0 range is returned.
    ///
    /// - Important: The values returned here **do not match**
    ///   ``sampleGrid(width:height:)`` (nor ``texture(width:height:)`` /
    ///   ``image(width:height:)``, which are built on it). Only the grid's first sample
    ///   coincides, at `sample(x: origin.x, y: origin.y)`; `sample(x: origin.x + Float(i)
    ///   * sampleScale.x, y: origin.y)` does not reproduce the grid's `i`-th value,
    ///   because GameplayKit steps `GKNoiseMap` on its own terms. See
    ///   ``GKNoiseWrapper`` for the full picture.
    /// - Parameters:
    ///   - x: The x coordinate, in noise space.
    ///   - y: The y coordinate, in noise space.
    /// - Returns: The noise value at the given point.
    public func sample(x: Float, y: Float) -> Float {
        let raw = gkNoise.value(atPosition: vector_float2(x, y))
        return config.normalized ? (raw + 1.0) * 0.5 : raw
    }

    /// Samples the noise value at a 2D point (Double-precision input).
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    /// - Returns: The noise value at the given point.
    public func sample(x: Double, y: Double) -> Float {
        sample(x: Float(x), y: Float(y))
    }

    // MARK: - グリッドサンプリング

    /// Generates noise values as a 2D grid.
    ///
    /// The grid starts at ``NoiseConfig/origin`` and spans
    /// `sampleScale × (width, height)` of noise space, so ``NoiseConfig/sampleScale``
    /// decides how much noise a grid of a given size covers. Both are handed to
    /// `GKNoiseMap`, which walks the grid itself.
    ///
    /// - Important: This is a different coordinate space from ``sample(x:y:)``, which
    ///   applies neither `origin` nor `sampleScale`. Index `(0, 0)` equals
    ///   `sample(x: origin.x, y: origin.y)`, but no other index lines up: GameplayKit
    ///   does not step the map by `origin + index × sampleScale`, and the step it does
    ///   use changes with `width` / `height` — the same `sampleScale` on a 64×64 and a
    ///   16×16 grid puts index `(1, 0)` at different points in the noise. Read the field
    ///   through one entry point per sketch rather than expecting the two to agree.
    /// - Parameters:
    ///   - width: The grid width, in samples.
    ///   - height: The grid height, in samples.
    /// - Returns: A flat, row-major array of noise values.
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

    // MARK: - テクスチャ生成

    /// Generates a grayscale BGRA8 noise texture.
    ///
    /// - Note: Built on ``sampleGrid(width:height:)``, so ``NoiseConfig/origin`` and
    ///   ``NoiseConfig/sampleScale`` apply here and the pixels do not correspond to
    ///   ``sample(x:y:)`` values.
    /// - Parameters:
    ///   - width: The texture width, in pixels.
    ///   - height: The texture height, in pixels.
    /// - Returns: A Metal texture containing the noise, or nil on failure.
    public func texture(width: Int, height: Int) -> MTLTexture? {
        let values = sampleGrid(width: width, height: height)
        return NoiseTextureBuilder.buildTexture(
            device: device, values: values, width: width, height: height
        )
    }

    /// Generates a noise image.
    ///
    /// - Note: Built on ``sampleGrid(width:height:)``, so ``NoiseConfig/origin`` and
    ///   ``NoiseConfig/sampleScale`` apply here and the pixels do not correspond to
    ///   ``sample(x:y:)`` values.
    /// - Parameters:
    ///   - width: The image width, in pixels.
    ///   - height: The image height, in pixels.
    /// - Returns: An image generated from the noise, or nil on failure.
    public func image(width: Int, height: Int) -> MImage? {
        guard let tex = texture(width: width, height: height) else { return nil }
        return MImage(texture: tex)
    }

    /// Generates a color-mapped noise texture using gradient stops.
    ///
    /// - Note: Built on ``sampleGrid(width:height:)``, so ``NoiseConfig/origin`` and
    ///   ``NoiseConfig/sampleScale`` apply here and the pixels do not correspond to
    ///   ``sample(x:y:)`` values.
    /// - Parameters:
    ///   - width: The texture width, in pixels.
    ///   - height: The texture height, in pixels.
    ///   - colorStops: An array of (position, BGRA color) pairs defining the
    ///     gradient. At least 2 stops are required; passing an empty array or
    ///     a single stop returns nil.
    /// - Returns: A Metal texture containing the color-mapped noise, or nil
    ///   if fewer than 2 color stops are given or texture allocation fails.
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

    // MARK: - 合成操作

    /// Composites another noise source by addition.
    /// - Parameter other: The noise wrapper to add.
    public func add(_ other: GKNoiseWrapper) {
        gkNoise.add(other.gkNoise)
        invalidateCache()
    }

    /// Composites another noise source by multiplication.
    /// - Parameter other: The noise wrapper to multiply by.
    public func multiply(_ other: GKNoiseWrapper) {
        gkNoise.multiply(other.gkNoise)
        invalidateCache()
    }

    /// Inverts the output value.
    public func invert() {
        gkNoise.invert()
        invalidateCache()
    }

    /// Applies an absolute value to the output.
    public func applyAbsoluteValue() {
        gkNoise.applyAbsoluteValue()
        invalidateCache()
    }

    /// Applies turbulence distortion to the noise.
    /// - Parameters:
    ///   - frequency: The frequency of the turbulence.
    ///   - power: The strength of the turbulence.
    ///   - roughness: The octave count of the turbulence.
    ///   - seed: The seed value of the turbulence.
    public func applyTurbulence(frequency: Double, power: Double, roughness: Int, seed: Int32) {
        gkNoise.applyTurbulence(
            frequency: frequency,
            power: power,
            roughness: Int32(roughness),
            seed: seed
        )
        invalidateCache()
    }

    /// Clamps the output value to a range.
    /// - Parameters:
    ///   - min: The lower bound.
    ///   - max: The upper bound.
    public func clamp(min: Double, max: Double) {
        gkNoise.clamp(lowerBound: min, upperBound: max)
        invalidateCache()
    }

    /// Raises the output value to a power.
    /// - Parameter exponent: The exponent to apply.
    public func raiseToPower(_ exponent: Double) {
        gkNoise.raiseToPower(exponent)
        invalidateCache()
    }

    // MARK: - プライベート

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
