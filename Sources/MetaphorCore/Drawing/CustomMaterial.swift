import Metal

/// Represent a 3D material that uses a custom fragment shader.
///
/// Create an instance with `createMaterial()` and apply it with `material()`.
/// While applied, Canvas3D drawing uses the custom fragment shader instead of the built-in one.
///
/// ```swift
/// let mat = try createMaterial(
///     source: BuiltinShaders.canvas3DStructs + myFragmentSource,
///     fragmentFunction: "myCustomFragment"
/// )
/// mat.setParameters(MyParams(color: SIMD3(1, 0, 0)))
/// material(mat)
/// box(100)
/// noMaterial()
/// ```
@MainActor
public final class CustomMaterial {
    /// Name of the fragment shader function.
    public let fragmentFunctionName: String

    /// Name of the custom vertex shader function, or nil to use the built-in shader.
    public let vertexFunctionName: String?

    /// Compiled fragment function.
    private(set) var fragmentFunction: MTLFunction

    /// Compiled vertex function, or nil to use the built-in shader.
    private(set) var vertexFunction: MTLFunction?

    /// Registration key in the ShaderLibrary.
    let libraryKey: String

    /// Raw bytes of custom parameter data.
    private var parameterData: [UInt8]?

    /// Set custom parameters as raw bytes.
    ///
    /// The data is bound to `buffer(4)` in the shader.
    /// - Parameter value: Any type matching the GPU struct layout.
    public func setParameters<T>(_ value: T) {
        var val = value
        parameterData = withUnsafeBytes(of: &val) { Array($0) }
    }

    /// Return the stored parameter bytes, or nil if no parameters have been set.
    var parameters: [UInt8]? { parameterData }

    init(fragmentFunction: MTLFunction, functionName: String, libraryKey: String,
         vertexFunction: MTLFunction? = nil, vertexFunctionName: String? = nil) {
        self.fragmentFunction = fragmentFunction
        self.fragmentFunctionName = functionName
        self.libraryKey = libraryKey
        self.vertexFunction = vertexFunction
        self.vertexFunctionName = vertexFunctionName
    }

    // MARK: - Hot Reload

    /// Reload shader functions from the shader library to update this material.
    ///
    /// Call this after `ShaderLibrary.reload` so that the modified shader
    /// can be used for pipeline reconstruction.
    /// - Parameter shaderLibrary: The shader library containing the updated source.
    /// - Throws: `MetaphorError.material(.shaderNotFound)` if the function name is not found.
    public func reload(shaderLibrary: ShaderLibrary) throws {
        guard let fn = shaderLibrary.function(named: fragmentFunctionName, from: libraryKey) else {
            throw MetaphorError.material(.shaderNotFound(fragmentFunctionName))
        }
        self.fragmentFunction = fn

        if let vtxName = vertexFunctionName {
            guard let vf = shaderLibrary.function(named: vtxName, from: libraryKey) else {
                throw MetaphorError.material(.shaderNotFound(vtxName))
            }
            self.vertexFunction = vf
        }
    }
}

