import MetaphorCore
import MetaphorNoise

// MARK: - GameplayKit ノイズブリッジ

extension Sketch {
    /// GameplayKit ノイズジェネレーターを作成します。
    ///
    /// - Parameters:
    ///   - type: ノイズアルゴリズムのタイプ。
    ///   - config: ノイズ生成の設定。
    /// - Returns: 新しい ``MetaphorNoise/GKNoiseWrapper`` インスタンス。
    public func createNoise(_ type: NoiseType, config: NoiseConfig = NoiseConfig()) -> GKNoiseWrapper {
        GKNoiseWrapper(type: type, config: config, device: context.renderer.device)
    }

    /// ノイズテクスチャを画像として生成します（便利メソッド）。
    ///
    /// - Parameters:
    ///   - type: ノイズアルゴリズムのタイプ。
    ///   - width: テクスチャの幅（ピクセル単位）。
    ///   - height: テクスチャの高さ（ピクセル単位）。
    ///   - config: ノイズ生成の設定。
    /// - Returns: 生成されたノイズ画像。生成に失敗した場合は `nil`。
    public func noiseTexture(_ type: NoiseType, width: Int, height: Int, config: NoiseConfig = NoiseConfig()) -> MImage? {
        let noise = GKNoiseWrapper(type: type, config: config, device: context.renderer.device)
        return noise.image(width: width, height: height)
    }
}
