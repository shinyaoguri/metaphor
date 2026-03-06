import Testing
import Metal
import MetalPerformanceShaders
import simd
@testable import metaphor
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

// MARK: - FilterType MPS Cases Tests

@Suite("FilterType MPS Cases")
struct FilterTypeMPSTests {

    @Test("MPS blur case holds sigma")
    func mpsBlurCase() {
        let filter = FilterType.mpsBlur(sigma: 5.0)
        if case .mpsBlur(let sigma) = filter {
            #expect(sigma == 5.0)
        } else {
            Issue.record("Expected mpsBlur case")
        }
    }

    @Test("MPS sobel case")
    func mpsSobelCase() {
        let filter = FilterType.mpsSobel
        if case .mpsSobel = filter {
            // OK
        } else {
            Issue.record("Expected mpsSobel case")
        }
    }

    @Test("MPS laplacian case")
    func mpsLaplacianCase() {
        let filter = FilterType.mpsLaplacian
        if case .mpsLaplacian = filter {
            // OK
        } else {
            Issue.record("Expected mpsLaplacian case")
        }
    }

    @Test("MPS erode case holds radius")
    func mpsErodeCase() {
        let filter = FilterType.mpsErode(radius: 3)
        if case .mpsErode(let r) = filter {
            #expect(r == 3)
        } else {
            Issue.record("Expected mpsErode case")
        }
    }

    @Test("MPS dilate case holds radius")
    func mpsDilateCase() {
        let filter = FilterType.mpsDilate(radius: 2)
        if case .mpsDilate(let r) = filter {
            #expect(r == 2)
        } else {
            Issue.record("Expected mpsDilate case")
        }
    }

    @Test("MPS median case holds diameter")
    func mpsMedianCase() {
        let filter = FilterType.mpsMedian(diameter: 5)
        if case .mpsMedian(let d) = filter {
            #expect(d == 5)
        } else {
            Issue.record("Expected mpsMedian case")
        }
    }

    @Test("MPS threshold case holds value")
    func mpsThresholdCase() {
        let filter = FilterType.mpsThreshold(0.7)
        if case .mpsThreshold(let v) = filter {
            #expect(v == 0.7)
        } else {
            Issue.record("Expected mpsThreshold case")
        }
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
}
