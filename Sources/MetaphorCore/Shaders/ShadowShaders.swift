import Foundation

/// Shadow mapping shader function name constants.
///
/// MSL source code is loaded from bundled .txt resource files at runtime.
public enum ShadowShaders {

    /// Shadow shader function name constants.
    public enum FunctionName {
        /// MSL function name for the shadow depth vertex shader.
        public static let shadowDepthVertex = "metaphor_shadowDepthVertex"
    }
}
