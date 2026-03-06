import Metal
import simd

/// Apply a custom post-process effect using a user-defined MSL fragment shader.
///
/// Create with `createPostEffect()` and add to the chain with `addPostEffect(.custom(...))`.
///
/// ```swift
/// let effect = try createPostEffect(
///     name: "myEffect",
///     source: PostProcessShaders.commonStructs + """
///     fragment float4 myFragment(
///         PPVertexOut in [[stage_in]],
///         texture2d<float> tex [[texture(0)]],
///         constant PostProcessParams &params [[buffer(0)]]
///     ) {
///         constexpr sampler s(filter::linear);
///         float4 color = tex.sample(s, in.texCoord);
///         return float4(1.0 - color.rgb, color.a);
///     }
///     """,
///     fragmentFunction: "myFragment"
/// )
/// effect.intensity = 0.5
/// addPostEffect(.custom(effect))
/// ```
@MainActor
public final class CustomPostEffect: PostEffect {
    /// The name of this effect.
    public let name: String

    /// The fragment shader function name.
    public let fragmentFunctionName: String

    /// The key under which the shader is registered in ShaderLibrary.
    let libraryKey: String

    /// The effect intensity, mapped to PostProcessParams.intensity.
    public var intensity: Float = 0

    /// The threshold value, mapped to PostProcessParams.threshold.
    public var threshold: Float = 0

    /// The radius value, mapped to PostProcessParams.radius.
    public var radius: Float = 0

    /// The smoothness value, mapped to PostProcessParams.smoothness.
    public var smoothness: Float = 0

    /// Raw bytes for custom parameter data bound to buffer(1).
    private var parameterData: [UInt8] = []

    init(name: String, fragmentFunctionName: String, libraryKey: String) {
        self.name = name
        self.fragmentFunctionName = fragmentFunctionName
        self.libraryKey = libraryKey
    }

    /// Set custom parameters to pass to the shader as buffer(1).
    ///
    /// Use this to send any plain-old-data struct to the fragment shader.
    /// ```swift
    /// struct MyParams {
    ///     var amount: Float
    ///     var color: SIMD3<Float>
    /// }
    /// effect.setParameters(MyParams(amount: 0.5, color: SIMD3(1, 0, 0)))
    /// ```
    ///
    /// - Parameter value: A POD struct whose bytes are copied to the GPU buffer.
    public func setParameters<T>(_ value: T) {
        var val = value
        parameterData = withUnsafeBytes(of: &val) { Array($0) }
    }

    /// Return the raw byte array of the custom parameters.
    var parameters: [UInt8] { parameterData }

    /// Indicate whether custom parameters have been set.
    var hasCustomParameters: Bool { !parameterData.isEmpty }

    // MARK: - PostEffect

    public func apply(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer, context: PostEffectContext) {
        let texelSize = SIMD2<Float>(1.0 / Float(input.width), 1.0 / Float(input.height))
        let params = PostProcessParams(
            texelSize: texelSize,
            intensity: intensity,
            threshold: threshold,
            radius: radius,
            smoothness: smoothness
        )
        context.renderPass(
            commandBuffer: commandBuffer,
            input: input, output: output,
            fragmentName: fragmentFunctionName,
            params: params,
            libraryKey: libraryKey,
            customParams: hasCustomParameters ? parameters : nil
        )
    }

    // MARK: - Hot Reload

    /// Re-fetch the shader function from the shader library after a hot reload.
    ///
    /// Call this after `ShaderLibrary.reload()` to ensure the post-effect pipeline
    /// rebuilds with the updated shader.
    ///
    /// - Parameter shaderLibrary: The shader library to look up the function from.
    /// - Throws: `MetaphorError.shaderNotFound` if the function is not found.
    public func reload(shaderLibrary: ShaderLibrary) throws {
        guard shaderLibrary.function(named: fragmentFunctionName, from: libraryKey) != nil else {
            throw MetaphorError.shaderNotFound(fragmentFunctionName)
        }
        // The function itself is fetched by PostProcessPipeline via libraryKey + fragmentFunctionName,
        // so clearing the function cache in ShaderLibrary.reload() triggers re-fetching automatically.
    }
}
