/// Canvas2D instanced drawing shader function name constants.
///
/// MSL source code is loaded from bundled .txt resource files at runtime.
/// Uses `instance_id` to read per-instance data (transform, color),
/// allowing batch rendering of identical shapes in a single draw call.
enum Canvas2DInstancedShaders {

    // MARK: - Function Names

    /// MSL function name for the instanced vertex shader.
    static let vertexFunctionName = "metaphor_canvas2DInstancedVertex"
    /// MSL function name for the instanced fragment shader.
    static let fragmentFunctionName = "metaphor_canvas2DInstancedFragment"
    /// MSL function name for the instanced difference blend fragment shader.
    static let differenceFragmentFunctionName = "metaphor_canvas2DInstancedDifferenceFragment"
    /// MSL function name for the instanced exclusion blend fragment shader.
    static let exclusionFragmentFunctionName = "metaphor_canvas2DInstancedExclusionFragment"
}
