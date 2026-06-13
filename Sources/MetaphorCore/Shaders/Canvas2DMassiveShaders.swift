/// Canvas2D massive drawing shader function names.
///
/// The MSL source is loaded from bundled shader resources and provides a compact
/// per-circle instance path for explicit bulk drawing APIs such as `circles()`.
enum Canvas2DMassiveShaders {

    /// Massive circle vertex shader.
    static let circleVertexFunctionName = "metaphor_canvas2DMassiveCircleVertex"
    /// Massive circle fragment shader.
    static let fragmentFunctionName = "metaphor_canvas2DMassiveFragment"
    /// Massive circle difference-blend fragment shader.
    static let differenceFragmentFunctionName = "metaphor_canvas2DMassiveDifferenceFragment"
    /// Massive circle exclusion-blend fragment shader.
    static let exclusionFragmentFunctionName = "metaphor_canvas2DMassiveExclusionFragment"
}
