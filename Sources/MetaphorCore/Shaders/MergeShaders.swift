import Foundation

/// Texture merge (compositing) shader function name constants.
///
/// MSL source code is loaded from bundled .txt resource files at runtime.
/// Blends two textures using a specified blend mode via a compute kernel.
/// Supported blend_mode values: 0=add, 1=alpha, 2=multiply, 3=screen.
public enum MergeShaders {

    /// Merge shader function name constants.
    public enum FunctionName {
        /// MSL function name for the texture merge compute kernel.
        public static let mergeTextures = "metaphor_mergeTextures"
    }
}
