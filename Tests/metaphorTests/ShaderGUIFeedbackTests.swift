import Testing
import Metal
import simd
@testable import metaphor

// MARK: - C-11: Shader Hot Reload

@Suite("C-11 Shader Hot Reload")
@MainActor
struct ShaderHotReloadTests {

    @Test("ShaderLibrary reload replaces library and clears function cache")
    func reloadClearsCacheAndReregisters() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let source1 = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void myKernel(uint gid [[thread_position_in_grid]]) {}
        """
        let key = "test.hotreload"
        try library.register(source: source1, as: key)

        // 関数を取得してキャッシュに入れる
        let fn1 = library.function(named: "myKernel", from: key)
        #expect(fn1 != nil)

        // reload で再登録
        let source2 = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void myKernel(uint gid [[thread_position_in_grid]]) {}
        kernel void myKernel2(uint gid [[thread_position_in_grid]]) {}
        """
        try library.reload(key: key, source: source2)

        // 新しい関数が取得できる
        let fn2 = library.function(named: "myKernel2", from: key)
        #expect(fn2 != nil)

        // 古い関数もまだ名前で取得可能（再登録されたソースに含まれるため）
        let fn1Again = library.function(named: "myKernel", from: key)
        #expect(fn1Again != nil)
    }

    @Test("invalidateFunctionCache clears cached functions")
    func invalidateFunctionCache() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void cacheTestKernel(uint gid [[thread_position_in_grid]]) {}
        """
        let key = "test.cache"
        try library.register(source: source, as: key)

        // キャッシュに入れる
        _ = library.function(named: "cacheTestKernel", from: key)

        // キャッシュクリア
        library.invalidateFunctionCache(for: key)

        // ライブラリは残っているので再取得可能
        let fn = library.function(named: "cacheTestKernel", from: key)
        #expect(fn != nil)
    }

    @Test("CustomMaterial reload updates fragment function")
    func customMaterialReload() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)

        let source = """
        #include <metal_stdlib>
        using namespace metal;

        \(BuiltinShaders.canvas3DStructs)

        struct Canvas3DVertexOut {
            float4 position [[position]];
            float3 worldPosition;
            float3 normal;
            float4 color;
        };

        fragment float4 reloadTestFrag(
            Canvas3DVertexOut in [[stage_in]],
            constant Canvas3DUniforms &uniforms [[buffer(1)]],
            constant Light3D *lights [[buffer(2)]],
            constant Material3D &material [[buffer(3)]]
        ) {
            return in.color;
        }
        """

        let key = "test.material.reloadTest"
        try library.register(source: source, as: key)
        let fn = library.function(named: "reloadTestFrag", from: key)!

        let mat = CustomMaterial(fragmentFunction: fn, functionName: "reloadTestFrag", libraryKey: key)

        // reload（同じソース）
        library.invalidateFunctionCache(for: key)
        try mat.reload(shaderLibrary: library)

        #expect(mat.fragmentFunctionName == "reloadTestFrag")
    }

    @Test("Canvas3D clearCustomPipelineCache works")
    func canvas3DClearCache() throws {
        let renderer = MetaphorRenderer()!
        let canvas3D = try Canvas3D(renderer: renderer)
        // キャッシュクリアがクラッシュしないこと
        canvas3D.clearCustomPipelineCache()
    }
}

// MARK: - C-12: GUI Parameter Control

@Suite("C-12 ParameterGUI")
@MainActor
struct ParameterGUITests {

    @Test("ParameterGUI initializes with default values")
    func guiDefaults() {
        let gui = ParameterGUI()
        #expect(gui.isVisible == true)
        #expect(gui.widgetWidth == 200)
        #expect(gui.fontSize == 12)
    }

    @Test("begin/end cycle works without crash")
    func beginEndCycle() {
        let gui = ParameterGUI()
        gui.begin()
        let (x, y, w, h) = gui.end()
        #expect(x == 10)
        #expect(y == 10)
        #expect(w > 0)
        #expect(h > 0)
    }

    @Test("isVisible=false makes slider skip")
    func invisibleSkip() {
        let gui = ParameterGUI()
        gui.isVisible = false
        gui.begin()
        // slider は呼べるがスキップされる（クラッシュしない）
        let (_, _, _, h) = gui.end()
        #expect(h > 0)
    }

    @Test("SketchContext has gui property")
    func sketchContextGUI() {
        let renderer = MetaphorRenderer()!
        let canvas = try! Canvas2D(renderer: renderer)
        let canvas3D = try! Canvas3D(renderer: renderer)
        let ctx = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)
        #expect(ctx.gui.isVisible == true)
    }
}

// MARK: - C-13: Offline Deterministic Rendering

@Suite("C-13 Offline Rendering")
@MainActor
struct OfflineRenderingTests {

    @Test("offlineFrameRate defaults to 60")
    func defaultFrameRate() {
        let renderer = MetaphorRenderer()!
        #expect(renderer.offlineFrameRate == 60.0)
        #expect(renderer.isOfflineRendering == false)
    }

    @Test("elapsedTime uses frame index in offline mode")
    func offlineElapsedTime() {
        let renderer = MetaphorRenderer()!
        renderer.isOfflineRendering = true
        renderer.offlineFrameRate = 30.0
        renderer.resetOfflineRendering()

        // フレーム 0 → elapsed = 0
        #expect(renderer.elapsedTime == 0.0)
    }

    @Test("offlineDeltaTime returns correct value")
    func offlineDeltaTime() {
        let renderer = MetaphorRenderer()!
        renderer.offlineFrameRate = 30.0
        let dt = renderer.offlineDeltaTime
        #expect(abs(dt - 1.0 / 30.0) < 0.0001)
    }

    @Test("isOfflineRendering can be set directly")
    func setOfflineFlag() {
        let renderer = MetaphorRenderer()!
        #expect(renderer.isOfflineRendering == false)
        renderer.isOfflineRendering = true
        #expect(renderer.isOfflineRendering == true)
        renderer.isOfflineRendering = false
        #expect(renderer.isOfflineRendering == false)
    }

    @Test("resetOfflineRendering resets elapsed to 0")
    func resetOffline() {
        let renderer = MetaphorRenderer()!
        renderer.isOfflineRendering = true
        renderer.offlineFrameRate = 30.0
        renderer.resetOfflineRendering()
        #expect(renderer.elapsedTime == 0.0)
    }

    @Test("SketchContext offline render API")
    func sketchContextOffline() {
        let renderer = MetaphorRenderer()!
        let canvas = try! Canvas2D(renderer: renderer)
        let canvas3D = try! Canvas3D(renderer: renderer)
        let ctx = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        #expect(ctx.isOfflineRendering == false)
        ctx.beginOfflineRender(fps: 24)
        #expect(ctx.isOfflineRendering == true)
        #expect(renderer.offlineFrameRate == 24.0)
        ctx.endOfflineRender()
        #expect(ctx.isOfflineRendering == false)
    }
}

// MARK: - C-14: FBO Feedback

@Suite("C-14 FBO Feedback")
@MainActor
struct FBOFeedbackTests {

    @Test("feedbackEnabled defaults to false")
    func defaultDisabled() {
        let renderer = MetaphorRenderer()!
        #expect(renderer.feedbackEnabled == false)
        #expect(renderer.previousFrameTexture == nil)
    }

    @Test("enableFeedback sets flag")
    func enableDisable() {
        let renderer = MetaphorRenderer()!
        let canvas = try! Canvas2D(renderer: renderer)
        let canvas3D = try! Canvas3D(renderer: renderer)
        let ctx = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        ctx.enableFeedback()
        #expect(renderer.feedbackEnabled == true)
        ctx.disableFeedback()
        #expect(renderer.feedbackEnabled == false)
    }

    @Test("previousFrame returns nil when feedback disabled")
    func previousFrameNilWhenDisabled() {
        let renderer = MetaphorRenderer()!
        let canvas = try! Canvas2D(renderer: renderer)
        let canvas3D = try! Canvas3D(renderer: renderer)
        let ctx = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        let img = ctx.previousFrame()
        #expect(img == nil)
    }

    @Test("previousFrameTexture is nil before any render")
    func previousFrameTextureNilInitially() {
        let renderer = MetaphorRenderer()!
        renderer.feedbackEnabled = true
        // renderFrame() を呼ばない状態では nil
        #expect(renderer.previousFrameTexture == nil)
    }
}

// MARK: - C-15: Indirect Draw Particle

@Suite("C-15 Indirect Draw Particle")
@MainActor
struct IndirectDrawParticleTests {

    @Test("ParticleSystem useIndirectDraw defaults to false")
    func defaultsOff() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let ps = try ParticleSystem(device: device, shaderLibrary: library, sampleCount: 4, count: 1000)
        #expect(ps.useIndirectDraw == false)
    }

    @Test("ParticleSystem can enable indirect draw")
    func enableIndirectDraw() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let ps = try ParticleSystem(device: device, shaderLibrary: library, sampleCount: 4, count: 1000)
        ps.useIndirectDraw = true
        #expect(ps.useIndirectDraw == true)
    }

    @Test("ParticleSystem with indirect draw doesn't crash on update")
    func indirectDrawUpdate() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try ShaderLibrary(device: device)
        let ps = try ParticleSystem(device: device, shaderLibrary: library, sampleCount: 4, count: 100)
        ps.useIndirectDraw = true

        let queue = device.makeCommandQueue()!
        let cb = queue.makeCommandBuffer()!
        let encoder = cb.makeComputeCommandEncoder()!
        ps.update(encoder: encoder, deltaTime: 1.0 / 60.0, time: 0.0)
        encoder.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        // クラッシュしなければ成功
    }
}
