/// Canvas3D instanced drawing shader function name constants.
///
/// MSL source code is loaded from bundled .txt resource files at runtime.
/// Uses `instance_id` to read per-instance data (transform, color),
/// allowing batch rendering of identical meshes in a single draw call.
enum Canvas3DInstancedShaders {

    // MARK: - Function Names

    /// MSL function name for the untextured instanced vertex shader.
    static let vertexFunctionName = "metaphor_canvas3DInstancedVertex"
    /// MSL function name for the untextured instanced fragment shader.
    static let fragmentFunctionName = "metaphor_canvas3DInstancedFragment"
    /// MSL function name for the textured instanced vertex shader.
    static let texturedVertexFunctionName = "metaphor_canvas3DTexInstancedVertex"
    /// MSL function name for the textured instanced fragment shader.
    static let texturedFragmentFunctionName = "metaphor_canvas3DTexInstancedFragment"
}
