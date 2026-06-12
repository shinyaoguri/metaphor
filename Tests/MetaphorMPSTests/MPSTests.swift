import Testing
import Metal
import simd
@testable import MetaphorCore
@testable import MetaphorMPS

// MARK: - MetaphorError.mps Tests

@Suite("MetaphorError.mps")
struct MPSErrorTests {

    @Test("error descriptions contain context")
    func errorDescriptions() {
        let errors: [MetaphorError] = [
            .mps(.deviceNotSupported),
            .mps(.accelerationStructureBuildFailed("test reason")),
            .mps(.textureOperationFailed("texture issue")),
            .mps(.intersectionFailed("ray miss")),
            .mps(.invalidScene("no meshes")),
        ]
        for error in errors {
            let desc = error.errorDescription ?? ""
            #expect(desc.contains("[metaphor]"))
        }
    }

    @Test("deviceNotSupported message")
    func deviceNotSupported() {
        let error = MetaphorError.mps(.deviceNotSupported)
        #expect(error.errorDescription?.contains("Metal Performance Shaders") == true)
    }

    @Test("accelerationStructureBuildFailed includes detail")
    func accelBuildFailed() {
        let error = MetaphorError.mps(.accelerationStructureBuildFailed("vertex buffer too small"))
        #expect(error.errorDescription?.contains("vertex buffer too small") == true)
    }

    @Test("textureOperationFailed includes detail")
    func textureOpFailed() {
        let error = MetaphorError.mps(.textureOperationFailed("format mismatch"))
        #expect(error.errorDescription?.contains("format mismatch") == true)
    }

    @Test("intersectionFailed includes detail")
    func intersectionFailed() {
        let error = MetaphorError.mps(.intersectionFailed("no hits"))
        #expect(error.errorDescription?.contains("no hits") == true)
    }

    @Test("invalidScene includes detail")
    func invalidScene() {
        let error = MetaphorError.mps(.invalidScene("empty"))
        #expect(error.errorDescription?.contains("empty") == true)
    }
}

// MARK: - MPS PostEffect Classes Tests

@Suite("MPS PostEffect Classes")
@MainActor
struct PostEffectMPSTests {

    @Test("MPS blur post effect")
    func mpsBlurPostEffect() {
        let effect = MPSBlurEffect(sigma: 3.0)
        #expect(effect.sigma == 3.0)
        #expect(effect.name == "mpsBlur")
    }

    @Test("MPS sobel post effect")
    func mpsSobelPostEffect() {
        let effect = MPSSobelEffect()
        #expect(effect.name == "mpsSobel")
    }

    @Test("MPS erode post effect")
    func mpsErodePostEffect() {
        let effect = MPSErodeEffect(radius: 2)
        #expect(effect.radius == 2)
        #expect(effect.name == "mpsErode")
    }

    @Test("MPS dilate post effect")
    func mpsDilatePostEffect() {
        let effect = MPSDilateEffect(radius: 1)
        #expect(effect.radius == 1)
        #expect(effect.name == "mpsDilate")
    }
}

// MARK: - RayTraceMode Tests

@Suite("RayTraceMode")
struct RayTraceModeTests {

    @Test("ambient occlusion mode defaults")
    func aoDefaults() {
        let mode = RayTraceMode.ambientOcclusion()
        if case .ambientOcclusion(let samples, let radius) = mode {
            #expect(samples == 16)
            #expect(radius == 2.0)
        } else {
            Issue.record("Expected ambientOcclusion case")
        }
    }

    @Test("ambient occlusion mode custom")
    func aoCustom() {
        let mode = RayTraceMode.ambientOcclusion(samples: 64, radius: 5.0)
        if case .ambientOcclusion(let samples, let radius) = mode {
            #expect(samples == 64)
            #expect(radius == 5.0)
        } else {
            Issue.record("Expected ambientOcclusion case")
        }
    }

    @Test("soft shadow mode")
    func softShadow() {
        let dir = SIMD3<Float>(1, 2, 3)
        let mode = RayTraceMode.softShadow(lightDirection: dir, softness: 0.2, samples: 32)
        if case .softShadow(let ld, let s, let n) = mode {
            #expect(ld == dir)
            #expect(s == 0.2)
            #expect(n == 32)
        } else {
            Issue.record("Expected softShadow case")
        }
    }

    @Test("diffuse mode")
    func diffuse() {
        let mode = RayTraceMode.diffuse
        if case .diffuse = mode {
            // OK
        } else {
            Issue.record("Expected diffuse case")
        }
    }
}

// MARK: - RayTraceUniforms Tests

@Suite("RayTraceUniforms")
struct RayTraceUniformsTests {

    @Test("struct layout")
    func structLayout() {
        let uniforms = RayTraceUniforms(
            inverseView: matrix_identity_float4x4,
            inverseProjection: matrix_identity_float4x4,
            width: 512, height: 512,
            sampleIndex: 0, totalSamples: 16,
            aoRadius: 2.0, shadowSoftness: 0.1,
            maxBounces: 3, padding: 0
        )
        #expect(uniforms.width == 512)
        #expect(uniforms.height == 512)
        #expect(uniforms.aoRadius == 2.0)
        #expect(uniforms.maxBounces == 3)
    }
}

// MARK: - MPSImageFilterWrapper Tests (GPU-dependent)

@Suite("MPSImageFilterWrapper")
struct MPSImageFilterWrapperTests {

    @Test("initialization")
    @MainActor func initialization() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return // No GPU available
        }
        let wrapper = MPSImageFilterWrapper(device: device, commandQueue: queue)
        _ = wrapper  // Verify construction succeeds
    }
}

// MARK: - MPSRayTracer Tests (GPU-dependent)

@Suite("MPSRayTracer")
struct MPSRayTracerTests {

    /// Check if the GPU supports ray tracing acceleration structures.
    /// CI runners (e.g. GitHub Actions macos-14) use a GPU serializer that
    /// does not implement `setAccelerationStructure:atBufferIndex:`.
    private static var gpuSupportsRayTracing: Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return device.supportsRaytracing
    }

    @Test("initialization compiles shaders")
    @MainActor func initialization() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return
        }
        let rt = try MPSRayTracer(device: device, commandQueue: queue, width: 64, height: 64)
        #expect(rt.outputTexture != nil)
        #expect(rt.outputTexture?.width == 64)
        #expect(rt.outputTexture?.height == 64)
    }

    @Test("clearScene resets state")
    @MainActor func clearScene() throws {
        guard Self.gpuSupportsRayTracing else { return }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return
        }
        let rt = try MPSRayTracer(device: device, commandQueue: queue, width: 32, height: 32)
        let mesh = try Mesh.box(device: device)
        rt.addMesh(mesh)
        rt.clearScene()
        // After clear, building should fail due to empty scene
        #expect(throws: MetaphorError.self) {
            try rt.buildAccelerationStructure()
        }
    }

    @Test("add mesh and build acceleration structure")
    @MainActor func addMeshAndBuild() throws {
        guard Self.gpuSupportsRayTracing else { return }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return
        }
        let rt = try MPSRayTracer(device: device, commandQueue: queue, width: 32, height: 32)
        let mesh = try Mesh.box(device: device)
        rt.addMesh(mesh)
        try rt.buildAccelerationStructure()
    }

    @Test("trace diffuse produces output")
    @MainActor func traceDiffuse() throws {
        guard Self.gpuSupportsRayTracing else { return }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return
        }
        let rt = try MPSRayTracer(device: device, commandQueue: queue, width: 32, height: 32)
        let mesh = try Mesh.box(device: device)
        rt.addMesh(mesh)
        try rt.buildAccelerationStructure()

        rt.trace(
            mode: .diffuse,
            camera: (eye: SIMD3(0, 2, 5), center: .zero, up: SIMD3(0, 1, 0), fov: .pi / 3)
        )
        #expect(rt.outputTexture != nil)
    }

    @Test("trace AO produces output")
    @MainActor func traceAO() throws {
        guard Self.gpuSupportsRayTracing else { return }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return
        }
        let rt = try MPSRayTracer(device: device, commandQueue: queue, width: 16, height: 16)
        let mesh = try Mesh.box(device: device)
        rt.addMesh(mesh)
        try rt.buildAccelerationStructure()

        rt.trace(
            mode: .ambientOcclusion(samples: 2, radius: 1.0),
            camera: (eye: SIMD3(0, 2, 5), center: .zero, up: SIMD3(0, 1, 0), fov: .pi / 3)
        )
        #expect(rt.outputTexture != nil)
    }

    @Test("add mesh with transform")
    @MainActor func addMeshWithTransform() throws {
        guard Self.gpuSupportsRayTracing else { return }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return
        }
        let rt = try MPSRayTracer(device: device, commandQueue: queue, width: 16, height: 16)
        let mesh = try Mesh.box(device: device)
        let t = float4x4(translation: SIMD3<Float>(0, 1, 0))
        rt.addMesh(mesh, transform: t)
        try rt.buildAccelerationStructure()
    }

    @Test("all-degenerate scene throws invalidScene")
    @MainActor func allDegenerateThrows() throws {
        guard Self.gpuSupportsRayTracing else { return }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return
        }
        let rt = try MPSRayTracer(device: device, commandQueue: queue, width: 16, height: 16)
        let dm = DynamicMesh(device: device)
        // 3 coincident vertices → zero-area triangle
        dm.addVertex(0, 0, 0)
        dm.addVertex(0, 0, 0)
        dm.addVertex(0, 0, 0)
        dm.addIndex(0); dm.addIndex(1); dm.addIndex(2)
        rt.addDynamicMesh(dm)
        #expect(throws: MetaphorError.self) {
            try rt.buildAccelerationStructure()
        }
    }

    @Test("mixed scene drops only degenerate triangles")
    @MainActor func mixedSceneDropsDegenerate() throws {
        guard Self.gpuSupportsRayTracing else { return }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return
        }
        let rt = try MPSRayTracer(device: device, commandQueue: queue, width: 16, height: 16)
        let dm = DynamicMesh(device: device)
        // Valid triangle (positive area)
        dm.addVertex(0, 0, 0)
        dm.addVertex(1, 0, 0)
        dm.addVertex(0, 1, 0)
        // Degenerate triangle (collinear)
        dm.addVertex(2, 0, 0)
        dm.addVertex(3, 0, 0)
        dm.addVertex(4, 0, 0)
        dm.addIndex(0); dm.addIndex(1); dm.addIndex(2)
        dm.addIndex(3); dm.addIndex(4); dm.addIndex(5)
        rt.addDynamicMesh(dm)
        try rt.buildAccelerationStructure()  // Should succeed with 1 valid triangle
    }
}

// MARK: - MPS post effects through PostProcessPipeline

@Suite("MPS post effect execution", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MPSPostEffectExecutionTests {

    /// MPS エフェクトをパイプライン経由で実行し、出力テクスチャに実際に
    /// 書き込まれることを検証します（ping-pong テクスチャに .shaderWrite が
    /// ないと MPS destination 書き込みは validation アサート／未定義動作）。
    @Test("MPSBlurEffect writes blurred output via the pipeline ping-pong texture")
    func mpsBlurThroughPipeline() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = try #require(device.makeCommandQueue())
        let shaderLib = try ShaderLibrary(device: device)
        let pipeline = try PostProcessPipeline(device: device, commandQueue: queue, shaderLibrary: shaderLib)
        pipeline.add(MPSBlurEffect(sigma: 4))

        // 中央に白い 8x8 ブロックを持つソーステクスチャ
        let size = 64
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        let source = try #require(device.makeTexture(descriptor: desc))
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 28..<36 {
            for x in 28..<36 {
                let i = (y * size + x) * 4
                pixels[i] = 255; pixels[i + 1] = 255; pixels[i + 2] = 255; pixels[i + 3] = 255
            }
        }
        pixels.withUnsafeBytes { buf in
            source.replace(region: MTLRegionMake2D(0, 0, size, size),
                           mipmapLevel: 0, withBytes: buf.baseAddress!, bytesPerRow: size * 4)
        }

        let commandBuffer = try #require(queue.makeCommandBuffer())
        let output = pipeline.apply(source: source, commandBuffer: commandBuffer)
        #expect(output !== source, "Pipeline should route through its ping-pong texture")

        // private ストレージの出力を読み戻す
        let stagingDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        stagingDesc.storageMode = .shared
        let staging = try #require(device.makeTexture(descriptor: stagingDesc))
        let blit = try #require(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: output, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: size, height: size, depth: 1),
                  to: staging, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var out = [UInt8](repeating: 0, count: size * size * 4)
        staging.getBytes(&out, bytesPerRow: size * 4,
                         from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)

        // 中央はまだ明るく、ブロックの外（ブラーの裾）にもエネルギーが漏れている
        let centerIdx = (32 * size + 32) * 4
        #expect(out[centerIdx] > 30, "Center should remain bright after blur (got \(out[centerIdx]))")
        let tailIdx = (32 * size + 40) * 4  // ブロック境界から 4px 外側
        #expect(out[tailIdx] > 0, "Blur tail should spread outside the block (got \(out[tailIdx]))")
        let farIdx = (4 * size + 4) * 4
        #expect(out[farIdx] < 10, "Far corner should stay dark (got \(out[farIdx]))")
    }
}
