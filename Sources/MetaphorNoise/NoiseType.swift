import simd

/// 利用可能な GameplayKit ノイズアルゴリズムを定義します。
public enum NoiseType: Sendable {
    /// パーリンノイズ（GKPerlinNoiseSource ベース）。
    case perlin
    /// Voronoi / Worley ノイズ（セルパターン、有機的テクスチャ）。
    case voronoi
    /// Billow ノイズ（柔らかい雲のようなパターン）。
    case billow
    /// Ridged マルチフラクタルノイズ（山岳地形、稲妻パターン）。
    case ridged
    /// 同心円シリンダーパターン。
    case cylinders
    /// 同心球パターン。
    case spheres
    /// チェッカーボードパターン。
    case checkerboard
    /// 定数値ノイズ。
    case constant(value: Double)
}

/// GKNoise 生成のパラメータを設定します。
public struct NoiseConfig: Sendable {
    /// フラクタルオクターブ数（デフォルトは6）。
    public var octaves: Int

    /// 基本周波数（デフォルトは1.0）。
    public var frequency: Double

    /// ラクナリティ（オクターブ間の周波数乗数、デフォルトは2.0）。
    public var lacunarity: Double

    /// ノイズジェネレーターのシード値。
    public var seed: Int32

    /// オクターブごとの振幅減衰率（パーシステンス、デフォルトは0.5）。
    public var persistence: Double

    /// 出力正規化の有効化（0.0〜1.0 にリマップ）。
    public var normalized: Bool

    /// Voronoi 固有: 距離をノイズ値として使用。
    public var voronoiDistanceEnabled: Bool

    /// サンプリングスケール（noiseMap の sampleSize にマッピング）。
    public var sampleScale: SIMD2<Double>

    /// サンプリングオフセット。
    public var origin: SIMD2<Double>

    /// 指定パラメータでノイズ設定を作成します。
    /// - Parameters:
    ///   - octaves: フラクタルオクターブ数（デフォルトは6）。
    ///   - frequency: 基本周波数（デフォルトは1.0）。
    ///   - lacunarity: オクターブ間の周波数乗数（デフォルトは2.0）。
    ///   - seed: シード値（デフォルトは0）。
    ///   - persistence: 振幅減衰率（デフォルトは0.5）。
    ///   - normalized: 出力を 0.0〜1.0 にリマップ（デフォルトは true）。
    ///   - voronoiDistanceEnabled: 距離を Voronoi 値として使用（デフォルトは true）。
    ///   - sampleScale: サンプリングスケール（デフォルトは (1.0, 1.0)）。
    ///   - origin: サンプリングオフセット（デフォルトはゼロ）。
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
