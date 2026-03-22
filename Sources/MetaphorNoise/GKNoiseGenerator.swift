import GameplayKit
import Metal
import MetaphorCore
import simd

/// GameplayKit ノイズシステムをラップし、プロシージャルノイズ生成を提供します。
///
/// 複数のノイズアルゴリズム（Voronoi、Billow、Ridged など）をサポートし、
/// ポイントサンプリングとテクスチャ生成の両方を提供します。
///
/// ```swift
/// let noise = createNoise(.voronoi)
/// let value = noise.sample(x: 0.5, y: 0.3)
/// let tex = noise.texture(width: 512, height: 512)
/// ```
@MainActor
public final class GKNoiseWrapper {
    /// ノイズタイプを返します。
    public let type: NoiseType

    /// ノイズ設定にアクセスまたは変更します。
    public var config: NoiseConfig {
        didSet { invalidateCache() }
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

    /// 2Dポイントでのノイズ値をサンプリングします。
    ///
    /// `config.normalized` が true の場合、返される値は 0.0〜1.0 の範囲です。
    /// それ以外では、-1.0〜1.0 の生の範囲が返されます。
    /// - Parameters:
    ///   - x: X 座標。
    ///   - y: Y 座標。
    /// - Returns: 指定ポイントでのノイズ値。
    public func sample(x: Float, y: Float) -> Float {
        let raw = gkNoise.value(atPosition: vector_float2(x, y))
        return config.normalized ? (raw + 1.0) * 0.5 : raw
    }

    /// 2Dポイントでのノイズ値をサンプリングします（Double 精度入力）。
    /// - Parameters:
    ///   - x: X 座標。
    ///   - y: Y 座標。
    /// - Returns: 指定ポイントでのノイズ値。
    public func sample(x: Double, y: Double) -> Float {
        sample(x: Float(x), y: Float(y))
    }

    // MARK: - グリッドサンプリング

    /// ノイズ値を2Dグリッドとして生成します。
    /// - Parameters:
    ///   - width: グリッドの幅（サンプル数）。
    ///   - height: グリッドの高さ（サンプル数）。
    /// - Returns: 行優先順序のノイズ値フラット配列。
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

    /// グレースケール BGRA8 ノイズテクスチャを生成します。
    /// - Parameters:
    ///   - width: テクスチャの幅（ピクセル単位）。
    ///   - height: テクスチャの高さ（ピクセル単位）。
    /// - Returns: ノイズを含む Metal テクスチャ。失敗時は nil。
    public func texture(width: Int, height: Int) -> MTLTexture? {
        let values = sampleGrid(width: width, height: height)
        return NoiseTextureBuilder.buildTexture(
            device: device, values: values, width: width, height: height
        )
    }

    /// ノイズ画像を生成します。
    /// - Parameters:
    ///   - width: 画像の幅（ピクセル単位）。
    ///   - height: 画像の高さ（ピクセル単位）。
    /// - Returns: ノイズから生成された画像。失敗時は nil。
    public func image(width: Int, height: Int) -> MImage? {
        guard let tex = texture(width: width, height: height) else { return nil }
        return MImage(texture: tex)
    }

    /// グラデーションストップを使用してカラーマップされたノイズテクスチャを生成します。
    /// - Parameters:
    ///   - width: テクスチャの幅（ピクセル単位）。
    ///   - height: テクスチャの高さ（ピクセル単位）。
    ///   - colorStops: グラデーションを定義する (位置, BGRA カラー) ペアの配列。
    /// - Returns: カラーマップされたノイズの Metal テクスチャ。失敗時は nil。
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

    /// 別のノイズソースを加算して合成します。
    /// - Parameter other: 加算するノイズラッパー。
    public func add(_ other: GKNoiseWrapper) {
        gkNoise.add(other.gkNoise)
        invalidateCache()
    }

    /// 別のノイズソースを乗算して合成します。
    /// - Parameter other: 乗算するノイズラッパー。
    public func multiply(_ other: GKNoiseWrapper) {
        gkNoise.multiply(other.gkNoise)
        invalidateCache()
    }

    /// 出力値を反転します。
    public func invert() {
        gkNoise.invert()
        invalidateCache()
    }

    /// 出力に絶対値を適用します。
    public func applyAbsoluteValue() {
        gkNoise.applyAbsoluteValue()
        invalidateCache()
    }

    /// ノイズにタービュレンスディストーションを適用します。
    /// - Parameters:
    ///   - frequency: タービュレンスの周波数。
    ///   - power: タービュレンスの強度。
    ///   - roughness: タービュレンスのオクターブ数。
    ///   - seed: タービュレンスのシード値。
    public func applyTurbulence(frequency: Double, power: Double, roughness: Int, seed: Int32) {
        gkNoise.applyTurbulence(
            frequency: frequency,
            power: power,
            roughness: Int32(roughness),
            seed: seed
        )
        invalidateCache()
    }

    /// 出力値を範囲内にクランプします。
    /// - Parameters:
    ///   - min: 下限。
    ///   - max: 上限。
    public func clamp(min: Double, max: Double) {
        gkNoise.clamp(lowerBound: min, upperBound: max)
        invalidateCache()
    }

    /// 出力値を指数で累乗します。
    /// - Parameter exponent: 適用する指数。
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
