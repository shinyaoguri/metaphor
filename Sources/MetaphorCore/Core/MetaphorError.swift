import Metal

/// Central error type for the metaphor library.
///
/// ## Error handling conventions
/// - **Initialization failures**: throw ``MetaphorError``
/// - **Runtime failures** (during draw): log with `metaphorWarning()`, do not throw
/// - **Standalone modules** (Audio, Network, Physics): use their own error types
public enum MetaphorError: Error, CustomStringConvertible, LocalizedError {

    // MARK: - Core (device, queue, buffer, texture)

    /// The Metal device could not be obtained.
    case deviceNotAvailable

    /// A texture could not be created with the specified dimensions and format.
    case textureCreationFailed(width: Int, height: Int, format: String)

    /// The Metal command queue could not be created.
    case commandQueueCreationFailed

    /// A Metal buffer could not be allocated.
    case bufferCreationFailed(size: Int)

    /// The sketch context is not available (called outside `setup()` or `draw()`).
    case contextUnavailable(method: String)

    // MARK: - Shader & Pipeline

    /// A shader failed to compile.
    case shaderCompilationFailed(name: String, underlying: Error)

    /// A render pipeline state could not be created.
    case pipelineCreationFailed(name: String, underlying: Error)

    /// The specified shader function was not found in the shader library.
    case shaderNotFound(String)

    // MARK: - Canvas

    /// A Canvas2D operation failed.
    case canvas(CanvasFailure)

    // MARK: - Geometry & Mesh

    /// A mesh operation failed.
    case mesh(MeshFailure)

    // MARK: - Image

    /// An image operation failed.
    case image(ImageFailure)

    // MARK: - Material

    /// A material operation failed.
    case material(MaterialFailure)

    // MARK: - Particle

    /// A particle system operation failed.
    case particle(ParticleFailure)

    // MARK: - MPS (Metal Performance Shaders)

    /// A Metal Performance Shaders operation failed.
    case mps(MPSFailure)

    // MARK: - RenderGraph

    /// A render graph operation failed.
    case renderGraph(RenderGraphFailure)

    // MARK: - Export

    /// An export operation failed.
    case export(ExportFailure)

    // MARK: - Compute

    /// A compute kernel operation failed.
    case compute(ComputeFailure)

    // MARK: - Nested Failure Types

    public enum CanvasFailure: Sendable {
        /// A Metal buffer for canvas vertices could not be created.
        case bufferCreationFailed
    }

    public enum MeshFailure: Sendable {
        /// The mesh file was not found.
        case fileNotFound
        /// The mesh data could not be parsed.
        case parseError(String)
    }

    public enum ImageFailure: Sendable {
        /// The source image is invalid or could not be converted to a CGImage.
        case invalidImage
    }

    public enum MaterialFailure: Sendable {
        /// The specified shader function was not found.
        case shaderNotFound(String)
    }

    public enum ParticleFailure: Sendable {
        /// GPU buffer allocation failed.
        case bufferCreationFailed
        /// A required shader function was not found.
        case shaderNotFound(String)
    }

    public enum MPSFailure: Sendable {
        /// The device does not support Metal Performance Shaders.
        case deviceNotSupported
        /// The acceleration structure failed to build.
        case accelerationStructureBuildFailed(String)
        /// A texture operation failed.
        case textureOperationFailed(String)
        /// A ray intersection test failed.
        case intersectionFailed(String)
        /// The scene configuration is invalid.
        case invalidScene(String)
    }

    public enum RenderGraphFailure: Sendable {
        /// A required merge shader function was not found.
        case shaderNotFound(String)
    }

    public enum ExportFailure: Sendable {
        /// No frames were captured.
        case noFrames
        /// The image destination could not be created.
        case destinationCreationFailed
        /// Finalization of the output file failed.
        case finalizationFailed
        /// The AVAssetWriter encountered an error.
        case writerFailed(String)
        /// Recording was not active when endRecord() was called.
        case notRecording
    }

    public enum ComputeFailure: Sendable {
        /// The specified compute function was not found.
        case functionNotFound(String)
    }

    // MARK: - Description

    public var description: String {
        switch self {
        case .deviceNotAvailable:
            "[metaphor] Metal device is not available"
        case .textureCreationFailed(let w, let h, let format):
            "[metaphor] Failed to create \(format) texture (\(w)x\(h))"
        case .commandQueueCreationFailed:
            "[metaphor] Failed to create command queue"
        case .bufferCreationFailed(let size):
            "[metaphor] Failed to create buffer (size: \(size))"
        case .contextUnavailable(let method):
            "[metaphor] Sketch context is not available in \(method). Ensure this is called inside setup() or draw()."
        case .shaderCompilationFailed(let name, let err):
            "[metaphor] Failed to compile shader '\(name)': \(err)"
        case .pipelineCreationFailed(let name, let err):
            "[metaphor] Failed to create pipeline '\(name)': \(err)"
        case .shaderNotFound(let name):
            "[metaphor] Shader function not found: '\(name)'"
        case .canvas(let f):
            switch f {
            case .bufferCreationFailed:
                "[metaphor] Failed to create canvas vertex buffer"
            }
        case .mesh(let f):
            switch f {
            case .fileNotFound:
                "[metaphor] Mesh file not found"
            case .parseError(let detail):
                "[metaphor] Mesh parse error: \(detail)"
            }
        case .image(let f):
            switch f {
            case .invalidImage:
                "[metaphor] Invalid image or CGImage conversion failed"
            }
        case .material(let f):
            switch f {
            case .shaderNotFound(let name):
                "[metaphor] Material shader not found: '\(name)'"
            }
        case .particle(let f):
            switch f {
            case .bufferCreationFailed:
                "[metaphor] Failed to create particle buffers"
            case .shaderNotFound(let name):
                "[metaphor] Particle shader not found: '\(name)'"
            }
        case .mps(let f):
            switch f {
            case .deviceNotSupported:
                "[metaphor] Device does not support Metal Performance Shaders"
            case .accelerationStructureBuildFailed(let detail):
                "[metaphor] MPS acceleration structure build failed: \(detail)"
            case .textureOperationFailed(let detail):
                "[metaphor] MPS texture operation failed: \(detail)"
            case .intersectionFailed(let detail):
                "[metaphor] MPS ray intersection failed: \(detail)"
            case .invalidScene(let detail):
                "[metaphor] Invalid MPS ray tracing scene: \(detail)"
            }
        case .renderGraph(let f):
            switch f {
            case .shaderNotFound(let name):
                "[metaphor] Render graph shader not found: '\(name)'"
            }
        case .export(let f):
            switch f {
            case .noFrames:
                "[metaphor] No frames captured for export"
            case .destinationCreationFailed:
                "[metaphor] Failed to create export destination"
            case .finalizationFailed:
                "[metaphor] Failed to finalize export file"
            case .writerFailed(let detail):
                "[metaphor] Video export failed: \(detail)"
            case .notRecording:
                "[metaphor] Export ended but was not recording"
            }
        case .compute(let f):
            switch f {
            case .functionNotFound(let name):
                "[metaphor] Compute function '\(name)' not found"
            }
        }
    }

    public var errorDescription: String? { description }
}

