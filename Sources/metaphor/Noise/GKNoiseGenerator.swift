import GameplayKit
import Metal
import simd

/// GameplayKit ノイズシステムのラッパー
///
/// 複数のノイズアルゴリズム（Voronoi, Billow, Ridged等）をサポートし、
/// ポイントサンプリングとテクスチャ生成の両方を提供する。
///
/// ```swift
/// let noise = createNoise(.voronoi)
/// let value = noise.sample(x: 0.5, y: 0.3)
/// let tex = noise.texture(width: 512, height: 512)
/// ```
@MainActor
public final class GKNoiseWrapper {
    /// ノイズタイプ
    public let type: NoiseType

    /// 設定
    public var config: NoiseConfig {
        didSet { invalidateCache() }
    }

    private var gkNoise: GKNoise
    private var cachedMap: GKNoiseMap?
    private var cachedMapSize: (Int, Int) = (0, 0)
    private let device: MTLDevice

    // MARK: - Initialization

    init(type: NoiseType, config: NoiseConfig = NoiseConfig(), device: MTLDevice) {
        self.type = type
        self.config = config
        self.device = device
        self.gkNoise = Self.makeGKNoise(type: type, config: config)
    }

    // MARK: - Point Sampling

    /// 2D ポイントサンプリング（normalized: 0.0〜1.0, otherwise: -1.0〜1.0）
    public func sample(x: Float, y: Float) -> Float {
        let raw = gkNoise.value(atPosition: vector_float2(x, y))
        return config.normalized ? (raw + 1.0) * 0.5 : raw
    }

    /// 2D ポイントサンプリング（Double 版）
    public func sample(x: Double, y: Double) -> Float {
        sample(x: Float(x), y: Float(y))
    }

    // MARK: - Grid Sampling

    /// 2D 配列としてノイズ値を生成
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

    /// ノイズテクスチャを生成（グレースケール BGRA8）
    public func texture(width: Int, height: Int) -> MTLTexture? {
        let values = sampleGrid(width: width, height: height)
        return NoiseTextureBuilder.buildTexture(
            device: device, values: values, width: width, height: height
        )
    }

    /// ノイズテクスチャを MImage として生成
    public func image(width: Int, height: Int) -> MImage? {
        guard let tex = texture(width: width, height: height) else { return nil }
        return MImage(texture: tex)
    }

    /// カラーマップ付きノイズテクスチャを生成
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

    /// ノイズを合成（加算）
    public func add(_ other: GKNoiseWrapper) {
        gkNoise.add(other.gkNoise)
        invalidateCache()
    }

    /// ノイズを合成（乗算）
    public func multiply(_ other: GKNoiseWrapper) {
        gkNoise.multiply(other.gkNoise)
        invalidateCache()
    }

    /// 出力値を反転
    public func invert() {
        gkNoise.invert()
        invalidateCache()
    }

    /// 絶対値
    public func applyAbsoluteValue() {
        gkNoise.applyAbsoluteValue()
        invalidateCache()
    }

    /// タービュレンスを適用
    public func applyTurbulence(frequency: Double, power: Double, roughness: Int, seed: Int32) {
        gkNoise.applyTurbulence(
            frequency: frequency,
            power: power,
            roughness: Int32(roughness),
            seed: seed
        )
        invalidateCache()
    }

    /// 値の範囲をクランプ
    public func clamp(min: Double, max: Double) {
        gkNoise.clamp(lowerBound: min, upperBound: max)
        invalidateCache()
    }

    /// 値をべき乗で変形
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
