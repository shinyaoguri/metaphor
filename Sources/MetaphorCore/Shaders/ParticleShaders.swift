import Foundation

/// GPU particle system shader function name constants.
///
/// MSL source code is loaded from bundled .txt resource files at runtime.
/// Includes compute kernels for particle update, indirect draw support
/// (counter reset, compact, build arguments), and vertex/fragment shaders
/// for billboard quad rendering with soft circle appearance.
enum ParticleShaders {

    /// Particle shader function name constants.
    enum FunctionName {
        /// MSL function name for the particle update compute kernel.
        static let update = "metaphor_particleUpdate"
        /// MSL function name for the particle billboard vertex shader.
        static let vertex = "metaphor_particleVertex"
        /// MSL function name for the particle soft-circle fragment shader.
        static let fragment = "metaphor_particleFragment"
        /// MSL function name for the atomic counter reset compute kernel.
        static let resetCounter = "metaphor_particleResetCounter"
        /// MSL function name for the alive-particle compaction compute kernel.
        static let compact = "metaphor_particleCompact"
        /// MSL function name for the indirect draw arguments builder compute kernel.
        static let buildIndirectArgs = "metaphor_particleBuildIndirectArgs"
    }
}
