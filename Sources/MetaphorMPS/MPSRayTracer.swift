@preconcurrency import Metal
import MetaphorCore
import simd

// MARK: - レイトレースモード

/// レイトレーシングのレンダリングモードを表します。
public enum RayTraceMode: Sendable {
    /// 設定可能なサンプル数と半径によるアンビエントオクルージョン。
    case ambientOcclusion(samples: Int = 16, radius: Float = 2.0)
    /// 平行光源からのソフトシャドウ。
    case softShadow(lightDirection: SIMD3<Float> = SIMD3(1, 2, 1), softness: Float = 0.1, samples: Int = 16)
    /// シンプルなディフューズシェーディング。
    case diffuse
}

// MARK: - RayTraceUniforms

/// レイトレーシング GPU シェーダーに渡されるユニフォームデータを格納します。
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

/// Metal ネイティブレイトレーシングシステムを提供します。
///
/// MTLAccelerationStructure と Metal Ray Tracing API を使用して、
/// GPU アクセラレーションによるレイトレーシングでアンビエントオクルージョン、
/// ソフトシャドウ、ディフューズシェーディングを行います。
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

    /// レイトレーシング結果テクスチャを返します。
    public var outputTexture: MTLTexture? { _outputTexture }

    // MARK: - 初期化

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

    /// レイトレーシングシーンにメッシュを追加します。
    /// - Parameters:
    ///   - mesh: 追加するメッシュ。
    ///   - transform: 適用するワールド空間の変換行列。
    public func addMesh(_ mesh: Mesh, transform: float4x4 = matrix_identity_float4x4) {
        scene.addMesh(mesh, transform: transform)
    }

    /// レイトレーシングシーンにダイナミックメッシュを追加します。
    /// - Parameters:
    ///   - mesh: 追加するダイナミックメッシュ。
    ///   - transform: 適用するワールド空間の変換行列。
    public func addDynamicMesh(_ mesh: DynamicMesh, transform: float4x4 = matrix_identity_float4x4) {
        scene.addDynamicMesh(mesh, transform: transform)
    }

    /// シーンからすべてのメッシュをクリアし、アクセラレーション構造をリセットします。
    public func clearScene() {
        scene.clear()
        accelerationStructure = nil
        normalBuffer = nil
    }

    /// 追加されたすべてのメッシュからアクセラレーション構造を構築します。
    ///
    /// メッシュを追加した後、レイをトレースする前に呼び出してください。
    /// - Throws: シーンが空またはバッファ作成に失敗した場合に `MetaphorError` をスローします。
    public func buildAccelerationStructure() throws {
        let result = try scene.buildAccelerationStructure(commandQueue: commandQueue)
        self.accelerationStructure = result.accelerationStructure
        self.normalBuffer = result.normalBuffer
    }

    // MARK: - パブリック: トレーシング

    /// 指定モードとカメラパラメータでレイトレーシングを実行します。
    /// - Parameters:
    ///   - mode: レンダリングモード（アンビエントオクルージョン、ソフトシャドウ、またはディフューズ）。
    ///   - camera: カメラパラメータ（視点位置、注視点、上方向ベクトル、視野角）。
    public func trace(
        mode: RayTraceMode,
        camera: (eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>, fov: Float)
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
            traceAO(accel: accel, output: output,
                     inverseView: inverseView, inverseProjection: inverseProjection,
                     samples: samples, radius: radius)

        case .softShadow(let lightDir, let softness, let samples):
            traceSoftShadow(accel: accel, output: output,
                            inverseView: inverseView, inverseProjection: inverseProjection,
                            lightDirection: lightDir, softness: softness, samples: samples)

        case .diffuse:
            traceDiffuse(accel: accel, output: output,
                         inverseView: inverseView, inverseProjection: inverseProjection)
        }
    }

    // MARK: - プライベート: AO トレーシング

    private func traceAO(
        accel: MTLAccelerationStructure,
        output: MTLTexture,
        inverseView: float4x4,
        inverseProjection: float4x4,
        samples: Int,
        radius: Float
    ) {
        guard let normalBuf = normalBuffer,
              let cb = commandQueue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder(),
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

        cb.commit()
        cb.waitUntilCompleted()
    }

    // MARK: - プライベート: ソフトシャドウ

    private func traceSoftShadow(
        accel: MTLAccelerationStructure,
        output: MTLTexture,
        inverseView: float4x4,
        inverseProjection: float4x4,
        lightDirection: SIMD3<Float>,
        softness: Float,
        samples: Int
    ) {
        guard let normalBuf = normalBuffer,
              let cb = commandQueue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder(),
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

        cb.commit()
        cb.waitUntilCompleted()
    }

    // MARK: - プライベート: ディフューズシェーディング

    private func traceDiffuse(
        accel: MTLAccelerationStructure,
        output: MTLTexture,
        inverseView: float4x4,
        inverseProjection: float4x4
    ) {
        guard let normalBuf = normalBuffer,
              let cb = commandQueue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder(),
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

        cb.commit()
        cb.waitUntilCompleted()
    }

    // MARK: - プライベート: セットアップ

    private func setupPipelines() throws {
        guard let source = ShaderLibrary.loadShaderSource("mpsRayTracer") else {
            throw MetaphorError.mps(.accelerationStructureBuildFailed("Failed to load mpsRayTracer shader source"))
        }

        let options = MTLCompileOptions()
        let lib = try device.makeLibrary(source: source, options: options)
        self.library = lib

        func makePipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = lib.makeFunction(name: name) else {
                throw MetaphorError.mps(.accelerationStructureBuildFailed("Shader function '\(name)' not found"))
            }
            let descriptor = MTLComputePipelineDescriptor()
            descriptor.computeFunction = fn
            return try device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
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
