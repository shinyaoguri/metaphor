import simd

/// ポストプロセスエフェクトの種類
public enum PostEffect: Sendable {
    /// ブルーム（高輝度部分のグロー）
    case bloom(intensity: Float = 1.0, threshold: Float = 0.8)

    /// カラーグレーディング
    case colorGrade(
        brightness: Float = 0.0,
        contrast: Float = 1.0,
        saturation: Float = 1.0,
        temperature: Float = 0.0
    )

    /// 色収差
    case chromaticAberration(intensity: Float = 0.005)

    /// ビネット
    case vignette(intensity: Float = 0.5, smoothness: Float = 0.5)

    /// 色反転
    case invert

    /// グレースケール
    case grayscale

    /// ガウシアンブラー
    case blur(radius: Float = 5.0)

    /// カスタムポストプロセスエフェクト
    case custom(CustomPostEffect)
}

/// ポストプロセスシェーダー用のユニフォーム構造体
struct PostProcessParams {
    var texelSize: SIMD2<Float> = .zero
    var intensity: Float = 0
    var threshold: Float = 0
    var brightness: Float = 0
    var contrast: Float = 1
    var saturation: Float = 1
    var temperature: Float = 0
    var radius: Float = 0
    var smoothness: Float = 0
    var _pad0: Float = 0
    var _pad1: Float = 0
}
