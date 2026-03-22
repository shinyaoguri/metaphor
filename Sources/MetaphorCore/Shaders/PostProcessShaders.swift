import Foundation

/// ポストプロセスエフェクトシェーダー関数名と共有構造体定義。
///
/// MSLソースコードはバンドルされた .txt リソースファイルからランタイムに読み込まれます。
/// 反転、グレースケール、ビネット、色収差、カラーグレーディング、
/// ガウシアンブラー（水平/垂直）、ブルーム抽出、ブルーム合成を含みます。
public enum PostProcessShaders {

    /// カスタムポストプロセスシェーダー用のMSL共通構造体定義。
    ///
    /// カスタムポストプロセスシェーダー記述時にプレフィックスとして使用します。
    /// ```swift
    /// let source = PostProcessShaders.commonStructs + """
    /// fragment float4 myEffect(
    ///     PPVertexOut in [[stage_in]],
    ///     texture2d<float> tex [[texture(0)]],
    ///     constant PostProcessParams &params [[buffer(0)]]
    /// ) {
    ///     // ...
    /// }
    /// """
    /// ```
    public static let commonStructs = """
    #include <metal_stdlib>
    using namespace metal;

    struct PPVertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    struct PostProcessParams {
        float2 texelSize;
        float  intensity;
        float  threshold;
        float  brightness;
        float  contrast;
        float  saturation;
        float  temperature;
        float  radius;
        float  smoothness;
        float  _pad0;
        float  _pad1;
    };
    """

    /// ポストプロセスシェーダー関数名定数。
    public enum FunctionName {
        /// 反転ポストプロセスシェーダーのMSL関数名。
        public static let postInvert = "metaphor_postInvert"
        /// グレースケールポストプロセスシェーダーのMSL関数名。
        public static let postGrayscale = "metaphor_postGrayscale"
        /// ビネットポストプロセスシェーダーのMSL関数名。
        public static let postVignette = "metaphor_postVignette"
        /// 色収差ポストプロセスシェーダーのMSL関数名。
        public static let postChromaticAberration = "metaphor_postChromaticAberration"
        /// カラーグレーディングポストプロセスシェーダーのMSL関数名。
        public static let postColorGrade = "metaphor_postColorGrade"
        /// 水平ガウシアンブラーポストプロセスシェーダーのMSL関数名。
        public static let postBlurH = "metaphor_postBlurH"
        /// 垂直ガウシアンブラーポストプロセスシェーダーのMSL関数名。
        public static let postBlurV = "metaphor_postBlurV"
        /// ブルーム抽出ポストプロセスシェーダーのMSL関数名。
        public static let postBloomExtract = "metaphor_postBloomExtract"
        /// ブルーム合成ポストプロセスシェーダーのMSL関数名。
        public static let postBloomComposite = "metaphor_postBloomComposite"
    }
}
