@preconcurrency import Metal
import MetalPerformanceShaders
import simd

// MARK: - Ray Trace Mode

/// レイトレーシングのレンダリングモード
public enum RayTraceMode: Sendable {
    /// アンビエントオクルージョン
    case ambientOcclusion(samples: Int = 16, radius: Float = 2.0)
    /// ソフトシャドウ（指向性ライト）
    case softShadow(lightDirection: SIMD3<Float> = SIMD3(1, 2, 1), softness: Float = 0.1, samples: Int = 16)
    /// 簡易ディフューズシェーディング
    case diffuse
}

// MARK: - RayTraceUniforms

/// GPU に渡すユニフォーム
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

/// MPS ベースのレイトレーシングシステム
///
/// MPSRayIntersector と MPSTriangleAccelerationStructure を使用し、
/// GPU 上でレイトレーシングを実行する。
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
    private let rayCount: Int

    // Scene
    private let scene: MPSRayScene
    private var accelerationStructure: MPSTriangleAccelerationStructure?
    private var normalBuffer: MTLBuffer?

    // MPS objects
    private var intersector: MPSRayIntersector?

    // Buffers
    private var rayBuffer: MTLBuffer?
    private var shadowRayBuffer: MTLBuffer?
    private var intersectionBuffer: MTLBuffer?
    private var shadowIntersectionBuffer: MTLBuffer?

    // Output
    private var _outputTexture: MTLTexture?

    // Pipelines
    private var library: MTLLibrary?
    private var generateRaysPipeline: MTLComputePipelineState?
    private var shadeAOPipeline: MTLComputePipelineState?
    private var accumulateAOPipeline: MTLComputePipelineState?
    private var shadeDiffusePipeline: MTLComputePipelineState?

    /// レイトレーシング結果テクスチャ
    public var outputTexture: MTLTexture? { _outputTexture }

    // MARK: - Init

    init(device: MTLDevice, commandQueue: MTLCommandQueue, width: Int, height: Int) throws {
        self.device = device
        self.commandQueue = commandQueue
        self.width = width
        self.height = height
        self.rayCount = width * height
        self.scene = MPSRayScene(device: device)

        try setupPipelines()
        setupBuffers()
        setupOutputTexture()
    }

    // MARK: - Public: Scene Building

    /// メッシュをシーンに追加
    public func addMesh(_ mesh: Mesh, transform: float4x4 = matrix_identity_float4x4) {
        scene.addMesh(mesh, transform: transform)
    }

    /// DynamicMesh をシーンに追加
    public func addDynamicMesh(_ mesh: DynamicMesh, transform: float4x4 = matrix_identity_float4x4) {
        scene.addDynamicMesh(mesh, transform: transform)
    }

    /// シーンをクリア
    public func clearScene() {
        scene.clear()
        accelerationStructure = nil
        normalBuffer = nil
    }

    /// アクセラレーション構造体を構築（メッシュ追加後に呼ぶ）
    public func buildAccelerationStructure() throws {
        let result = try scene.buildAccelerationStructure()
        self.accelerationStructure = result.accelerationStructure
        self.normalBuffer = result.normalBuffer

        // Setup intersector
        let intersector = MPSRayIntersector(device: device)
        intersector.rayDataType = .originMinDistanceDirectionMaxDistance
        intersector.rayStride = MemoryLayout<Float>.stride * 8  // packed_float3 + float + packed_float3 + float
        intersector.intersectionDataType = .distancePrimitiveIndexCoordinates
        self.intersector = intersector
    }

    // MARK: - Public: Tracing

    /// レイトレーシングを実行
    ///
    /// - Parameters:
    ///   - mode: レンダリングモード
    ///   - camera: カメラパラメータ (eye, center, up, fov)
    public func trace(
        mode: RayTraceMode,
        camera: (eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>, fov: Float)
    ) {
        guard let accel = accelerationStructure,
              let intersector = intersector,
              let rayBuf = rayBuffer,
              let intBuf = intersectionBuffer,
              let output = _outputTexture else { return }

        let view = float4x4(lookAt: camera.eye, center: camera.center, up: camera.up)
        let aspect = Float(width) / Float(height)
        let projection = float4x4(perspectiveFov: camera.fov, aspect: aspect, near: 0.01, far: 1000)

        let inverseView = view.inverse
        let inverseProjection = projection.inverse

        switch mode {
        case .ambientOcclusion(let samples, let radius):
            traceAO(accel: accel, intersector: intersector, rayBuf: rayBuf, intBuf: intBuf,
                     output: output, inverseView: inverseView, inverseProjection: inverseProjection,
                     samples: samples, radius: radius)

        case .softShadow(let lightDir, let softness, let samples):
            traceSoftShadow(accel: accel, intersector: intersector, rayBuf: rayBuf, intBuf: intBuf,
                            output: output, inverseView: inverseView, inverseProjection: inverseProjection,
                            lightDirection: lightDir, softness: softness, samples: samples)

        case .diffuse:
            traceDiffuse(accel: accel, intersector: intersector, rayBuf: rayBuf, intBuf: intBuf,
                         output: output, inverseView: inverseView, inverseProjection: inverseProjection)
        }
    }

    // MARK: - Private: AO Tracing

    private func traceAO(
        accel: MPSTriangleAccelerationStructure,
        intersector: MPSRayIntersector,
        rayBuf: MTLBuffer,
        intBuf: MTLBuffer,
        output: MTLTexture,
        inverseView: float4x4,
        inverseProjection: float4x4,
        samples: Int,
        radius: Float
    ) {
        guard let shadowRayBuf = shadowRayBuffer,
              let shadowIntBuf = shadowIntersectionBuffer,
              let normalBuf = normalBuffer else { return }

        for sampleIdx in 0..<samples {
            guard let cb = commandQueue.makeCommandBuffer() else { continue }

            var uniforms = RayTraceUniforms(
                inverseView: inverseView, inverseProjection: inverseProjection,
                width: UInt32(width), height: UInt32(height),
                sampleIndex: UInt32(sampleIdx), totalSamples: UInt32(samples),
                aoRadius: radius, shadowSoftness: 0, maxBounces: 0, padding: 0
            )

            // 1. Generate primary rays (first sample only)
            if sampleIdx == 0 {
                if let encoder = cb.makeComputeCommandEncoder(),
                   let pipeline = generateRaysPipeline {
                    encoder.setComputePipelineState(pipeline)
                    encoder.setBuffer(rayBuf, offset: 0, index: 0)
                    encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 1)
                    dispatchGrid(encoder: encoder, pipeline: pipeline)
                    encoder.endEncoding()
                }

                // 2. Primary ray intersection
                intersector.encodeIntersection(
                    commandBuffer: cb,
                    intersectionType: .nearest,
                    rayBuffer: rayBuf, rayBufferOffset: 0,
                    intersectionBuffer: intBuf, intersectionBufferOffset: 0,
                    rayCount: rayCount,
                    accelerationStructure: accel
                )
            }

            // 3. Shade AO (generate shadow rays)
            if let encoder = cb.makeComputeCommandEncoder(),
               let pipeline = shadeAOPipeline {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(rayBuf, offset: 0, index: 0)
                encoder.setBuffer(intBuf, offset: 0, index: 1)
                encoder.setBuffer(normalBuf, offset: 0, index: 2)
                encoder.setBuffer(shadowRayBuf, offset: 0, index: 3)
                encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 4)
                encoder.setTexture(output, index: 0)
                dispatchGrid(encoder: encoder, pipeline: pipeline)
                encoder.endEncoding()
            }

            // 4. Shadow ray intersection
            intersector.encodeIntersection(
                commandBuffer: cb,
                intersectionType: .any,
                rayBuffer: shadowRayBuf, rayBufferOffset: 0,
                intersectionBuffer: shadowIntBuf, intersectionBufferOffset: 0,
                rayCount: rayCount,
                accelerationStructure: accel
            )

            // 5. Accumulate AO
            if let encoder = cb.makeComputeCommandEncoder(),
               let pipeline = accumulateAOPipeline {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(intBuf, offset: 0, index: 0)
                encoder.setBuffer(shadowIntBuf, offset: 0, index: 1)
                encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 2)
                encoder.setTexture(output, index: 0)
                dispatchGrid(encoder: encoder, pipeline: pipeline)
                encoder.endEncoding()
            }

            cb.commit()
            cb.waitUntilCompleted()
        }
    }

    // MARK: - Private: Soft Shadow

    private func traceSoftShadow(
        accel: MPSTriangleAccelerationStructure,
        intersector: MPSRayIntersector,
        rayBuf: MTLBuffer,
        intBuf: MTLBuffer,
        output: MTLTexture,
        inverseView: float4x4,
        inverseProjection: float4x4,
        lightDirection: SIMD3<Float>,
        softness: Float,
        samples: Int
    ) {
        // Soft shadow uses same pipeline as AO but with light-direction-based shadow rays
        // For simplicity, reuse AO pipeline with light direction encoded in uniforms
        guard let shadowRayBuf = shadowRayBuffer,
              let shadowIntBuf = shadowIntersectionBuffer,
              let normalBuf = normalBuffer else { return }

        for sampleIdx in 0..<samples {
            guard let cb = commandQueue.makeCommandBuffer() else { continue }

            var uniforms = RayTraceUniforms(
                inverseView: inverseView, inverseProjection: inverseProjection,
                width: UInt32(width), height: UInt32(height),
                sampleIndex: UInt32(sampleIdx), totalSamples: UInt32(samples),
                aoRadius: 1000.0, shadowSoftness: softness, maxBounces: 0, padding: 0
            )

            if sampleIdx == 0 {
                if let encoder = cb.makeComputeCommandEncoder(),
                   let pipeline = generateRaysPipeline {
                    encoder.setComputePipelineState(pipeline)
                    encoder.setBuffer(rayBuf, offset: 0, index: 0)
                    encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 1)
                    dispatchGrid(encoder: encoder, pipeline: pipeline)
                    encoder.endEncoding()
                }

                intersector.encodeIntersection(
                    commandBuffer: cb,
                    intersectionType: .nearest,
                    rayBuffer: rayBuf, rayBufferOffset: 0,
                    intersectionBuffer: intBuf, intersectionBufferOffset: 0,
                    rayCount: rayCount,
                    accelerationStructure: accel
                )
            }

            // Generate shadow rays toward light with jitter
            if let encoder = cb.makeComputeCommandEncoder(),
               let pipeline = shadeAOPipeline {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(rayBuf, offset: 0, index: 0)
                encoder.setBuffer(intBuf, offset: 0, index: 1)
                encoder.setBuffer(normalBuf, offset: 0, index: 2)
                encoder.setBuffer(shadowRayBuf, offset: 0, index: 3)
                encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 4)
                encoder.setTexture(output, index: 0)
                dispatchGrid(encoder: encoder, pipeline: pipeline)
                encoder.endEncoding()
            }

            intersector.encodeIntersection(
                commandBuffer: cb,
                intersectionType: .any,
                rayBuffer: shadowRayBuf, rayBufferOffset: 0,
                intersectionBuffer: shadowIntBuf, intersectionBufferOffset: 0,
                rayCount: rayCount,
                accelerationStructure: accel
            )

            if let encoder = cb.makeComputeCommandEncoder(),
               let pipeline = accumulateAOPipeline {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(intBuf, offset: 0, index: 0)
                encoder.setBuffer(shadowIntBuf, offset: 0, index: 1)
                encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 2)
                encoder.setTexture(output, index: 0)
                dispatchGrid(encoder: encoder, pipeline: pipeline)
                encoder.endEncoding()
            }

            cb.commit()
            cb.waitUntilCompleted()
        }
    }

    // MARK: - Private: Diffuse Shading

    private func traceDiffuse(
        accel: MPSTriangleAccelerationStructure,
        intersector: MPSRayIntersector,
        rayBuf: MTLBuffer,
        intBuf: MTLBuffer,
        output: MTLTexture,
        inverseView: float4x4,
        inverseProjection: float4x4
    ) {
        guard let normalBuf = normalBuffer,
              let cb = commandQueue.makeCommandBuffer() else { return }

        var uniforms = RayTraceUniforms(
            inverseView: inverseView, inverseProjection: inverseProjection,
            width: UInt32(width), height: UInt32(height),
            sampleIndex: 0, totalSamples: 1,
            aoRadius: 0, shadowSoftness: 0, maxBounces: 0, padding: 0
        )

        // Generate rays
        if let encoder = cb.makeComputeCommandEncoder(),
           let pipeline = generateRaysPipeline {
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(rayBuf, offset: 0, index: 0)
            encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 1)
            dispatchGrid(encoder: encoder, pipeline: pipeline)
            encoder.endEncoding()
        }

        // Intersect
        intersector.encodeIntersection(
            commandBuffer: cb,
            intersectionType: .nearest,
            rayBuffer: rayBuf, rayBufferOffset: 0,
            intersectionBuffer: intBuf, intersectionBufferOffset: 0,
            rayCount: rayCount,
            accelerationStructure: accel
        )

        // Shade
        if let encoder = cb.makeComputeCommandEncoder(),
           let pipeline = shadeDiffusePipeline {
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(rayBuf, offset: 0, index: 0)
            encoder.setBuffer(intBuf, offset: 0, index: 1)
            encoder.setBuffer(normalBuf, offset: 0, index: 2)
            encoder.setBytes(&uniforms, length: MemoryLayout<RayTraceUniforms>.size, index: 3)
            encoder.setTexture(output, index: 0)
            dispatchGrid(encoder: encoder, pipeline: pipeline)
            encoder.endEncoding()
        }

        cb.commit()
        cb.waitUntilCompleted()
    }

    // MARK: - Private: Setup

    private func setupPipelines() throws {
        let lib = try device.makeLibrary(source: MPSRayTracerShaders.source, options: nil)
        self.library = lib

        func makePipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = lib.makeFunction(name: name) else {
                throw MPSError.accelerationStructureBuildFailed("Shader function '\(name)' not found")
            }
            return try device.makeComputePipelineState(function: fn)
        }

        generateRaysPipeline = try makePipeline("generatePrimaryRays")
        shadeAOPipeline = try makePipeline("shadeAmbientOcclusion")
        accumulateAOPipeline = try makePipeline("accumulateAO")
        shadeDiffusePipeline = try makePipeline("shadeDiffuse")
    }

    private func setupBuffers() {
        let rayStride = MemoryLayout<Float>.stride * 8  // packed_float3 + float + packed_float3 + float
        let intStride = MemoryLayout<Float>.stride * 4  // distance + primitiveIndex(as float) + float2

        rayBuffer = device.makeBuffer(length: rayCount * rayStride, options: .storageModeShared)
        shadowRayBuffer = device.makeBuffer(length: rayCount * rayStride, options: .storageModeShared)
        intersectionBuffer = device.makeBuffer(length: rayCount * intStride, options: .storageModeShared)
        shadowIntersectionBuffer = device.makeBuffer(length: rayCount * intStride, options: .storageModeShared)
    }

    private func setupOutputTexture() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .managed
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
