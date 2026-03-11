/// MPS ray tracing shader function name constants.
///
/// MSL source code is loaded from bundled .txt resource files at runtime.
/// Includes primary ray generation, ambient occlusion shading and accumulation,
/// and simple diffuse shading with hemisphere lighting.
enum MPSRayTracerShaders {

    /// MPS ray tracer shader function name constants.
    enum FunctionName {
        /// MSL function name for primary ray generation.
        static let generatePrimaryRays = "generatePrimaryRays"
        /// MSL function name for ambient occlusion shading.
        static let shadeAmbientOcclusion = "shadeAmbientOcclusion"
        /// MSL function name for AO accumulation.
        static let accumulateAO = "accumulateAO"
        /// MSL function name for simple diffuse shading.
        static let shadeDiffuse = "shadeDiffuse"
    }
}
