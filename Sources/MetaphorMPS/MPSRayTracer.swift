import Metal
import MetaphorCore
import simd

// MARK: - レイトレースモード

/// Represents a ray-tracing render mode.
public enum RayTraceMode: Sendable {
    /// Ambient occlusion with configurable sample count and radius.
    case ambientOcclusion(samples: Int = 16, radius: Float = 2.0)
    /// Soft shadow from a directional light source.
    case softShadow(lightDirection: SIMD3<Float> = SIMD3(1, 2, 1), softness: Float = 0.1, samples: Int = 16)
    /// Simple diffuse shading.
    case diffuse
}

// MARK: - RayTraceUniforms

/// Holds the uniform data passed to the ray-tracing GPU shaders.
struct RayTraceUniforms {
    var inverseView: float4x4
    var inverseProjection: float4x4
    var width: UInt32
    var height: UInt32
    var sampleIndex: UInt32
    var totalSamples: UInt32
    var aoRadius: Float
    var shadowSoftness: Float
    var maxBounces: Int32
    var padding: Float
}

// MARK: - MPSRayTracer

/// Provides a Metal-native ray-tracing system.
///
/// Uses MTLAccelerationStructure and the Metal Ray Tracing API to perform
/// GPU-accelerated ray tracing for ambient occlusion, soft shadows, and
/// diffuse shading.
///
/// ```swift
/// let rt = try createRayTracer(width: 512, height: 512)
/// rt.addMesh(Mesh.box(device: renderer.device))
/// try rt.buildAccelerationStructure()
/// rt.trace(mode: .ambientOcclusion(samples: 32, radius: 2.0),
///          camera: (eye: SIMD3(0,2,5), center: .zero, up: SIMD3(0,1,0), fov: .pi/3))
/// ```
@MainActor
public final class MPSRayTracer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let width: Int
    private let height: Int

    // シーン
    private let scene: MPSRayScene
    private var accelerationStructure: MTLAccelerationStructure?
    private var normalBuffer: MTLBuffer?

    // 出力
    private var _outputTexture: MTLTexture?

    // パイプライン
    private var library: MTLLibrary?
    private var traceAOPipeline: MTLComputePipelineState?
    private var traceSoftShadowPipeline: MTLComputePipelineState?
    private var traceDiffusePipeline: MTLComputePipelineState?

    /// Returns the ray-tracing result texture.
    public var outputTexture: MTLTexture? { _outputTexture }

    // MARK: - 初期化

    /// Creates a ray tracer bound to the given device and output size.
    /// - Parameters:
    ///   - device: The Metal device used to compile shaders and build pipelines.
    ///   - commandQueue: The command queue used to encode ray-tracing work.
    ///   - width: The output texture width in pixels.
    ///   - height: The output texture height in pixels.
    /// - Throws: ``MetaphorError``. `MetaphorError.mps(.accelerationStructureBuildFailed)`
    ///   when the bundled shader source or a kernel function is missing,
    ///   `MetaphorError.shaderCompilationFailed` when the MSL source fails to compile,
    ///   and `MetaphorError.pipelineCreationFailed` when a compute pipeline cannot be built.
    public init(device: MTLDevice, commandQueue: MTLCommandQueue, width: Int, height: Int) throws {
        self.device = device
        self.commandQueue = commandQueue
        self.width = width
        self.height = height
        self.scene = MPSRayScene(device: device)

        try setupPipelines()
        setupOutputTexture()
    }

    // MARK: - パブリック: シーン構築

    /// Adds a mesh to the ray-tracing scene.
    /// - Parameters:
    ///   - mesh: The mesh to add.
    ///   - transform: The world-space transform matrix to apply.
    public func addMesh(_ mesh: Mesh, transform: float4x4 = matrix_identity_float4x4) {
        scene.addMesh(mesh, transform: transform)
    }

    /// Adds a dynamic mesh to the ray-tracing scene.
    /// - Parameters:
    ///   - mesh: The dynamic mesh to add.
    ///   - transform: The world-space transform matrix to apply.
    public func addDynamicMesh(_ mesh: DynamicMesh, transform: float4x4 = matrix_identity_float4x4) {
        scene.addDynamicMesh(mesh, transform: transform)
    }

    /// Clears all meshes from the scene and resets the acceleration structure.
    public func clearScene() {
        scene.clear()
        accelerationStructure = nil
        normalBuffer = nil
    }

    /// Builds an acceleration structure from all added meshes.
    ///
    /// Call this after adding meshes and before tracing rays.
    /// - Throws: `MetaphorError` if the scene is empty or buffer creation fails.
    public func buildAccelerationStructure() throws {
        let result = try scene.buildAccelerationStructure(commandQueue: commandQueue)
        self.accelerationStructure = result.accelerationStructure
        self.normalBuffer = result.normalBuffer
    }

    // MARK: - パブリック: トレーシング

    /// Performs ray tracing with the given mode and camera parameters.
    /// - Parameters:
    ///   - mode: The render mode (ambient occlusion, soft shadow, or diffuse).
    ///   - camera: The camera parameters (eye position, look-at center, up vector, field of view).
    public func trace(
        mode: RayTraceMode,
        camera: (eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>, fov: Float)
    ) {
        guard let cb = commandQueue.makeCommandBuffer() else { return }
        encodeTrace(mode: mode, camera: camera, commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
    }

    /// Encodes ray tracing for the given mode and camera parameters into an existing command buffer.
    ///
    /// This method does not call `commit()` or `waitUntilCompleted()`, so it can be
    /// combined into the same command buffer as the draw loop or other GPU work.
    /// - Parameters:
    ///   - mode: The render mode (ambient occlusion, soft shadow, or diffuse).
    ///   - camera: The camera parameters (eye position, look-at center, up vector, field of view).
    ///   - commandBuffer: The command buffer to encode into.
    public func encodeTrace(
        mode: RayTraceMode,
        camera: (eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>, fov: Float),
        commandBuffer: MTLCommandBuffer
    ) {
        guard let accel = accelerationStructure,
              let output = _outputTexture else { return }

        let view = float4x4(lookAt: camera.eye, center: camera.center, up: camera.up)
        let aspect = Float(width) / Float(height)
        let projection = float4x4(perspectiveFov: camera.fov, aspect: aspect, near: 0.01, far: 1000)

        let inverseView = view.inverse
        let inverseProjection = projection.inverse

        switch mode {
        case .ambientOcclusion(let samples, let radius):
            encodeTraceAO(
                accel: accel,
                output: output,
                inverseView: inverseView,
                inverseProjection: inverseProjection,
                samples: samples,
                radius: radius,
                commandBuffer: commandBuffer
            )

        case .softShadow(let lightDir, let softness, let samples):
            encodeTraceSoftShadow(
                accel: accel,
                output: output,
                inverseView: inverseView,
                inverseProjection: inverseProjection,
                lightDirection: lightDir,
                softness: softness,
                samples: samples,
                commandBuffer: commandBuffer
            )

        case .diffuse:
            encodeTraceDiffuse(
                accel: accel,
                output: output,
                inverseView: inverseView,
                inverseProjection: inverseProjection,
                commandBuffer: commandBuffer
            )
        }
    }

    // MARK: - プライベート: AO トレーシング

    private func encodeTraceAO(
        accel: MTLAccelerationStructure,
        output: MTLTexture,
        inverseView: float4x4,
        inverseProjection: float4x4,
        samples: Int,
        radius: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let normalBuf = normalBuffer,
              let encoder = commandBuffer.makeComputeCommandEncoder(),
              let pipeline = traceAOPipeline else { return }

        var uniforms = RayTraceUniforms(
            inverseView: inverseView, inverseProjection: inverseProjection,
            width: UInt32(width), height: UInt32(height),
            sampleIndex: 0, totalSamples: UInt32(samples),
            aoRadius: radius, shadowSoftness: 0, maxBounces: 0, padding: 0
        )

        encoder.setComputePipelineState(pipeline)
        encoder.setAccelerationStructure(accel, bufferIndex: 0)
        encoder.setBuffer(normalBuf, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 2)
        encoder.setTexture(output, index: 0)
        dispatchGrid(encoder: encoder, pipeline: pipeline)
        encoder.endEncoding()
    }

    // MARK: - プライベート: ソフトシャドウ

    private func encodeTraceSoftShadow(
        accel: MTLAccelerationStructure,
        output: MTLTexture,
        inverseView: float4x4,
        inverseProjection: float4x4,
        lightDirection: SIMD3<Float>,
        softness: Float,
        samples: Int,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let normalBuf = normalBuffer,
              let encoder = commandBuffer.makeComputeCommandEncoder(),
              let pipeline = traceSoftShadowPipeline else { return }

        var uniforms = RayTraceUniforms(
            inverseView: inverseView, inverseProjection: inverseProjection,
            width: UInt32(width), height: UInt32(height),
            sampleIndex: 0, totalSamples: UInt32(samples),
            aoRadius: 0, shadowSoftness: softness, maxBounces: 0, padding: 0
        )
        var lightDir = lightDirection

        encoder.setComputePipelineState(pipeline)
        encoder.setAccelerationStructure(accel, bufferIndex: 0)
        encoder.setBuffer(normalBuf, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 2)
        encoder.setBytes(&lightDir, length: MemoryLayout<SIMD3<Float>>.size, index: 3)
        encoder.setTexture(output, index: 0)
        dispatchGrid(encoder: encoder, pipeline: pipeline)
        encoder.endEncoding()
    }

    // MARK: - プライベート: ディフューズシェーディング

    private func encodeTraceDiffuse(
        accel: MTLAccelerationStructure,
        output: MTLTexture,
        inverseView: float4x4,
        inverseProjection: float4x4,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let normalBuf = normalBuffer,
              let encoder = commandBuffer.makeComputeCommandEncoder(),
              let pipeline = traceDiffusePipeline else { return }

        var uniforms = RayTraceUniforms(
            inverseView: inverseView, inverseProjection: inverseProjection,
            width: UInt32(width), height: UInt32(height),
            sampleIndex: 0, totalSamples: 1,
            aoRadius: 0, shadowSoftness: 0, maxBounces: 0, padding: 0
        )

        encoder.setComputePipelineState(pipeline)
        encoder.setAccelerationStructure(accel, bufferIndex: 0)
        encoder.setBuffer(normalBuf, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 2)
        encoder.setTexture(output, index: 0)
        dispatchGrid(encoder: encoder, pipeline: pipeline)
        encoder.endEncoding()
    }

    // MARK: - プライベート: セットアップ

    private func setupPipelines() throws {
        guard let source = ShaderLibrary.loadShaderSource("mpsRayTracer") else {
            throw MetaphorError.mps(.accelerationStructureBuildFailed("Failed to load mpsRayTracer shader source"))
        }

        let options = MTLCompileOptions()
        let lib: MTLLibrary
        do {
            lib = try device.makeLibrary(source: source, options: options)
        } catch {
            // Metal の生 NSError を素通りさせず MetaphorError へ包む
            throw MetaphorError.shaderCompilationFailed(name: "mpsRayTracer", underlying: error)
        }
        self.library = lib

        func makePipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = lib.makeFunction(name: name) else {
                throw MetaphorError.mps(.accelerationStructureBuildFailed("Shader function '\(name)' not found"))
            }
            let descriptor = MTLComputePipelineDescriptor()
            descriptor.computeFunction = fn
            do {
                return try device.makeComputePipelineState(
                    descriptor: descriptor, options: [], reflection: nil)
            } catch {
                throw MetaphorError.pipelineCreationFailed(name: name, underlying: error)
            }
        }

        traceAOPipeline = try makePipeline("traceAmbientOcclusion")
        traceSoftShadowPipeline = try makePipeline("traceSoftShadow")
        traceDiffusePipeline = try makePipeline("traceDiffuse")
    }

    private func setupOutputTexture() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        // Apple Silicon 専用のため UMA の .shared を使う（.managed は
        // CPU 読み出し時の synchronizeResource 漏れの温床になる）
        desc.storageMode = .shared
        _outputTexture = device.makeTexture(descriptor: desc)
    }

    private func dispatchGrid(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
    }
}
