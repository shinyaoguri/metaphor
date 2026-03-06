import Foundation

/// Post-processing effect shader function names and shared struct definitions.
///
/// MSL source code is loaded from bundled .txt resource files at runtime.
/// Includes invert, grayscale, vignette, chromatic aberration, color grading,
/// gaussian blur (horizontal/vertical), bloom extract, and bloom composite.
public enum PostProcessShaders {

    /// MSL common struct definitions for custom post-process shaders.
    ///
    /// Use as a prefix when writing custom post-process shaders.
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

    /// Post-process shader function name constants.
    public enum FunctionName {
        /// MSL function name for the invert post-process shader.
        public static let postInvert = "metaphor_postInvert"
        /// MSL function name for the grayscale post-process shader.
        public static let postGrayscale = "metaphor_postGrayscale"
        /// MSL function name for the vignette post-process shader.
        public static let postVignette = "metaphor_postVignette"
        /// MSL function name for the chromatic aberration post-process shader.
        public static let postChromaticAberration = "metaphor_postChromaticAberration"
        /// MSL function name for the color grading post-process shader.
        public static let postColorGrade = "metaphor_postColorGrade"
        /// MSL function name for the horizontal gaussian blur post-process shader.
        public static let postBlurH = "metaphor_postBlurH"
        /// MSL function name for the vertical gaussian blur post-process shader.
        public static let postBlurV = "metaphor_postBlurV"
        /// MSL function name for the bloom extract post-process shader.
        public static let postBloomExtract = "metaphor_postBloomExtract"
        /// MSL function name for the bloom composite post-process shader.
        public static let postBloomComposite = "metaphor_postBloomComposite"
    }
}
