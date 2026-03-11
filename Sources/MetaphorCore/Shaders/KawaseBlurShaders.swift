import Foundation

/// Kawase (dual-filter) blur shader function name constants.
///
/// MSL source code is loaded from bundled .txt resource files at runtime.
/// Achieves comparable quality to Gaussian blur at significantly higher speed
/// by using hierarchical down/upsample passes instead of per-pixel kernel loops.
enum KawaseBlurShaders {

    /// Kawase blur shader function name constants.
    enum FunctionName {
        /// MSL function name for the Kawase downsample shader.
        static let kawaseDownsample = "metaphor_kawaseDownsample"
        /// MSL function name for the Kawase upsample shader.
        static let kawaseUpsample = "metaphor_kawaseUpsample"
    }
}
