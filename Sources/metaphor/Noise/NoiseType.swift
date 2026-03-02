import simd

/// GameplayKit ノイズの種類
public enum NoiseType: Sendable {
    /// Perlin ノイズ（GKPerlinNoiseSource ベース）
    case perlin
    /// Voronoi / Worley ノイズ（セルパターン、有機テクスチャ）
    case voronoi
    /// ビローノイズ（柔らかい雲状パターン）
    case billow
    /// リッジマルチフラクタル（山岳地形、稲妻パターン）
    case ridged
    /// 同心円筒パターン
    case cylinders
    /// 同心球パターン
    case spheres
    /// チェッカーボードパターン
    case checkerboard
    /// 定数値ノイズ
    case constant(value: Double)
}

/// GKNoise の設定パラメータ
public struct NoiseConfig: Sendable {
    /// フラクタルのオクターブ数（デフォルト 6）
    public var octaves: Int

    /// 周波数（デフォルト 1.0）
    public var frequency: Double

    /// ラクナリティ（オクターブ間の周波数倍率、デフォルト 2.0）
    public var lacunarity: Double

    /// シード値
    public var seed: Int32

    /// 振幅の減衰率（Persistence、デフォルト 0.5）
    public var persistence: Double

    /// 出力の正規化（0.0〜1.0 に再マッピング）
    public var normalized: Bool

    /// Voronoi 固有: 距離をノイズ値に使用するか
    public var voronoiDistanceEnabled: Bool

    /// サンプリングスケール（noiseMap の sampleSize）
    public var sampleScale: SIMD2<Double>

    /// サンプリングオフセット
    public var origin: SIMD2<Double>

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
